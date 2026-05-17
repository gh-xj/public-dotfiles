package typewhisper

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"configctl/internal/report"
)

type Lexicon struct {
	Version       int        `json:"version"`
	Dictionary    Dictionary `json:"dictionary"`
	Snippets      []Snippet  `json:"snippets"`
	dictionarySet bool
	snippetsSet   bool
}

type Dictionary struct {
	Terms          []Term       `json:"terms"`
	Corrections    []Correction `json:"corrections"`
	termsSet       bool
	correctionsSet bool
}

type Term struct {
	Original      string `json:"original"`
	CaseSensitive bool   `json:"caseSensitive"`
	IsEnabled     bool   `json:"isEnabled"`
}

type Correction struct {
	Original       string `json:"original"`
	Replacement    string `json:"replacement"`
	CaseSensitive  bool   `json:"caseSensitive"`
	IsEnabled      bool   `json:"isEnabled"`
	replacementSet bool
}

type Snippet struct {
	Trigger        string `json:"trigger"`
	Replacement    string `json:"replacement"`
	CaseSensitive  bool   `json:"caseSensitive"`
	IsEnabled      bool   `json:"isEnabled"`
	replacementSet bool
}

type Summary struct {
	Terms       int `json:"terms"`
	Corrections int `json:"corrections"`
	Snippets    int `json:"snippets"`
}

func (l *Lexicon) UnmarshalJSON(data []byte) error {
	var raw struct {
		Version    int         `json:"version"`
		Dictionary *Dictionary `json:"dictionary"`
		Snippets   *[]Snippet  `json:"snippets"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	l.Version = raw.Version
	if raw.Dictionary != nil {
		l.Dictionary = *raw.Dictionary
		l.dictionarySet = true
	}
	if raw.Snippets != nil {
		l.Snippets = *raw.Snippets
		l.snippetsSet = true
	}
	return nil
}

func (d *Dictionary) UnmarshalJSON(data []byte) error {
	var raw struct {
		Terms       *[]Term       `json:"terms"`
		Corrections *[]Correction `json:"corrections"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	if raw.Terms != nil {
		d.Terms = *raw.Terms
		d.termsSet = true
	}
	if raw.Corrections != nil {
		d.Corrections = *raw.Corrections
		d.correctionsSet = true
	}
	return nil
}

func (t *Term) UnmarshalJSON(data []byte) error {
	var text string
	if err := json.Unmarshal(data, &text); err == nil {
		t.Original = strings.TrimSpace(text)
		t.CaseSensitive = false
		t.IsEnabled = true
		return nil
	}
	var raw struct {
		Original      string `json:"original"`
		CaseSensitive *bool  `json:"caseSensitive"`
		IsEnabled     *bool  `json:"isEnabled"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	t.Original = strings.TrimSpace(raw.Original)
	if raw.CaseSensitive != nil {
		t.CaseSensitive = *raw.CaseSensitive
	}
	t.IsEnabled = true
	if raw.IsEnabled != nil {
		t.IsEnabled = *raw.IsEnabled
	}
	return nil
}

func (c *Correction) UnmarshalJSON(data []byte) error {
	var raw struct {
		Original      string  `json:"original"`
		Replacement   *string `json:"replacement"`
		CaseSensitive *bool   `json:"caseSensitive"`
		IsEnabled     *bool   `json:"isEnabled"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	c.Original = strings.TrimSpace(raw.Original)
	if raw.Replacement != nil {
		c.Replacement = *raw.Replacement
		c.replacementSet = true
	}
	if raw.CaseSensitive != nil {
		c.CaseSensitive = *raw.CaseSensitive
	}
	c.IsEnabled = true
	if raw.IsEnabled != nil {
		c.IsEnabled = *raw.IsEnabled
	}
	return nil
}

func (s *Snippet) UnmarshalJSON(data []byte) error {
	var raw struct {
		Trigger       string  `json:"trigger"`
		Replacement   *string `json:"replacement"`
		CaseSensitive *bool   `json:"caseSensitive"`
		IsEnabled     *bool   `json:"isEnabled"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	s.Trigger = strings.TrimSpace(raw.Trigger)
	if raw.Replacement != nil {
		s.Replacement = *raw.Replacement
		s.replacementSet = true
	}
	if raw.CaseSensitive != nil {
		s.CaseSensitive = *raw.CaseSensitive
	}
	s.IsEnabled = true
	if raw.IsEnabled != nil {
		s.IsEnabled = *raw.IsEnabled
	}
	return nil
}

func LoadLexicon(path string) (Lexicon, []report.Diagnostic, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Lexicon{}, []report.Diagnostic{{
			Severity: "error",
			Code:     "typewhisper.lexicon.read_failed",
			Message:  err.Error(),
			Path:     path,
		}}, err
	}
	var lexicon Lexicon
	if err := json.Unmarshal(data, &lexicon); err != nil {
		return Lexicon{}, []report.Diagnostic{{
			Severity: "error",
			Code:     "typewhisper.lexicon.invalid_json",
			Message:  err.Error(),
			Path:     path,
		}}, err
	}
	diagnostics := ValidateLexicon(lexicon, path)
	if len(diagnostics) > 0 {
		return lexicon, diagnostics, fmt.Errorf("invalid TypeWhisper lexicon")
	}
	return lexicon, nil, nil
}

func ValidateLexicon(lexicon Lexicon, path string) []report.Diagnostic {
	var diagnostics []report.Diagnostic
	add := func(code, message string) {
		diagnostics = append(diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     code,
			Message:  message,
			Path:     path,
		})
	}
	if lexicon.Version != 1 {
		add("typewhisper.lexicon.version", "version must be 1")
	}
	if !lexicon.dictionarySet {
		add("typewhisper.lexicon.dictionary_missing", "dictionary must be present")
	}
	if !lexicon.Dictionary.termsSet {
		add("typewhisper.lexicon.terms_missing", "dictionary.terms must be present")
	}
	if !lexicon.Dictionary.correctionsSet {
		add("typewhisper.lexicon.corrections_missing", "dictionary.corrections must be present")
	}
	if !lexicon.snippetsSet {
		add("typewhisper.lexicon.snippets_missing", "snippets must be present")
	}
	for index, term := range lexicon.Dictionary.Terms {
		if strings.TrimSpace(term.Original) == "" {
			add("typewhisper.lexicon.term_blank", fmt.Sprintf("dictionary.terms[%d] must have a nonblank original", index))
		}
	}
	for index, correction := range lexicon.Dictionary.Corrections {
		if strings.TrimSpace(correction.Original) == "" {
			add("typewhisper.lexicon.correction_blank", fmt.Sprintf("dictionary.corrections[%d].original must be nonblank", index))
		}
		if !correction.replacementSet {
			add("typewhisper.lexicon.correction_replacement", fmt.Sprintf("dictionary.corrections[%d].replacement must be present", index))
		}
	}
	for index, snippet := range lexicon.Snippets {
		if strings.TrimSpace(snippet.Trigger) == "" {
			add("typewhisper.lexicon.snippet_trigger_blank", fmt.Sprintf("snippets[%d].trigger must be nonblank", index))
		}
		if !snippet.replacementSet || strings.TrimSpace(snippet.Replacement) == "" {
			add("typewhisper.lexicon.snippet_replacement_blank", fmt.Sprintf("snippets[%d].replacement must be nonblank", index))
		}
	}
	addDuplicateDiagnostics(&diagnostics, path, "typewhisper.lexicon.duplicate_term", "duplicate dictionary term", lowerKeys(lexicon.Dictionary.Terms, func(term Term) string {
		return term.Original
	}))
	addDuplicateDiagnostics(&diagnostics, path, "typewhisper.lexicon.duplicate_correction", "duplicate dictionary correction", lowerKeys(lexicon.Dictionary.Corrections, func(correction Correction) string {
		return correction.Original
	}))
	addDuplicateDiagnostics(&diagnostics, path, "typewhisper.lexicon.duplicate_snippet", "duplicate snippet trigger", exactKeys(lexicon.Snippets, func(snippet Snippet) string {
		return snippet.Trigger
	}))
	return diagnostics
}

func (l Lexicon) Summary() Summary {
	return Summary{
		Terms:       len(l.Dictionary.Terms),
		Corrections: len(l.Dictionary.Corrections),
		Snippets:    len(l.Snippets),
	}
}

func SummaryText(summary Summary) string {
	return fmt.Sprintf("%d terms, %d corrections, %d snippets", summary.Terms, summary.Corrections, summary.Snippets)
}

func addDuplicateDiagnostics(diagnostics *[]report.Diagnostic, path, code, message string, keys map[string]int) {
	for key, count := range keys {
		if key == "" || count < 2 {
			continue
		}
		*diagnostics = append(*diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     code,
			Message:  fmt.Sprintf("%s: %s", message, key),
			Path:     path,
		})
	}
}

func lowerKeys[T any](items []T, keyFn func(T) string) map[string]int {
	keys := make(map[string]int)
	for _, item := range items {
		keys[strings.ToLower(strings.TrimSpace(keyFn(item)))]++
	}
	return keys
}

func exactKeys[T any](items []T, keyFn func(T) string) map[string]int {
	keys := make(map[string]int)
	for _, item := range items {
		keys[strings.TrimSpace(keyFn(item))]++
	}
	return keys
}
