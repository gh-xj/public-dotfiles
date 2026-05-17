package typewhisper

import (
	"encoding/json"
	"testing"
)

func TestValidateLexiconAcceptsStringAndObjectTerms(t *testing.T) {
	raw := []byte(`{
	  "version": 1,
	  "dictionary": {
	    "terms": ["codex", {"original": "TypeWhisper", "caseSensitive": true}],
	    "corrections": [{"original": "codexx", "replacement": "codex"}]
	  },
	  "snippets": [{"trigger": ";sig", "replacement": "xj"}]
	}`)
	var lexicon Lexicon
	if err := json.Unmarshal(raw, &lexicon); err != nil {
		t.Fatal(err)
	}
	if diagnostics := ValidateLexicon(lexicon, "test.json"); len(diagnostics) != 0 {
		t.Fatalf("expected no diagnostics, got %#v", diagnostics)
	}
	if got := lexicon.Summary(); got.Terms != 2 || got.Corrections != 1 || got.Snippets != 1 {
		t.Fatalf("unexpected summary: %#v", got)
	}
	if !lexicon.Dictionary.Terms[1].CaseSensitive || !lexicon.Dictionary.Terms[1].IsEnabled {
		t.Fatalf("object term defaults were not applied: %#v", lexicon.Dictionary.Terms[1])
	}
}

func TestValidateLexiconRejectsDuplicates(t *testing.T) {
	raw := []byte(`{
	  "version": 1,
	  "dictionary": {
	    "terms": ["Codex", "codex"],
	    "corrections": []
	  },
	  "snippets": []
	}`)
	var lexicon Lexicon
	if err := json.Unmarshal(raw, &lexicon); err != nil {
		t.Fatal(err)
	}
	diagnostics := ValidateLexicon(lexicon, "test.json")
	if len(diagnostics) != 1 {
		t.Fatalf("expected one diagnostic, got %#v", diagnostics)
	}
	if diagnostics[0].Code != "typewhisper.lexicon.duplicate_term" {
		t.Fatalf("unexpected diagnostic: %#v", diagnostics[0])
	}
}

func TestValidateLexiconRequiresSnippetReplacement(t *testing.T) {
	raw := []byte(`{
	  "version": 1,
	  "dictionary": {"terms": [], "corrections": []},
	  "snippets": [{"trigger": ";x", "replacement": " "}]
	}`)
	var lexicon Lexicon
	if err := json.Unmarshal(raw, &lexicon); err != nil {
		t.Fatal(err)
	}
	diagnostics := ValidateLexicon(lexicon, "test.json")
	if len(diagnostics) != 1 {
		t.Fatalf("expected one diagnostic, got %#v", diagnostics)
	}
	if diagnostics[0].Code != "typewhisper.lexicon.snippet_replacement_blank" {
		t.Fatalf("unexpected diagnostic: %#v", diagnostics[0])
	}
}

func TestValidateLexiconRequiresTopLevelSections(t *testing.T) {
	raw := []byte(`{"version": 1}`)
	var lexicon Lexicon
	if err := json.Unmarshal(raw, &lexicon); err != nil {
		t.Fatal(err)
	}
	diagnostics := ValidateLexicon(lexicon, "test.json")
	if len(diagnostics) != 4 {
		t.Fatalf("expected four diagnostics, got %#v", diagnostics)
	}
}
