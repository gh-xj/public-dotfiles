package typewhisper

import (
	"context"
	"database/sql"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"time"

	"configctl/internal/report"

	_ "modernc.org/sqlite"
)

type StorePaths struct {
	StoreDir        string `json:"store_dir"`
	DictionaryStore string `json:"dictionary_store"`
	SnippetsStore   string `json:"snippets_store"`
}

type StoreStatus struct {
	StoreDir             string `json:"store_dir"`
	DictionaryStore      string `json:"dictionary_store"`
	SnippetsStore        string `json:"snippets_store"`
	Terms                int    `json:"terms"`
	Corrections          int    `json:"corrections"`
	Snippets             int    `json:"snippets"`
	TypeWhisperRunning   bool   `json:"typewhisper_running"`
	DictionaryStoreFound bool   `json:"dictionary_store_found"`
	SnippetsStoreFound   bool   `json:"snippets_store_found"`
}

type ChangeCounts struct {
	Updates    int `json:"updates"`
	Insertions int `json:"insertions"`
}

type ImportPlan struct {
	Lexicon            Summary      `json:"lexicon"`
	Dictionary         ChangeCounts `json:"dictionary"`
	Snippets           ChangeCounts `json:"snippets"`
	TypeWhisperRunning bool         `json:"typewhisper_running"`
}

type ImportResult struct {
	Plan      ImportPlan `json:"plan"`
	BackupDir string     `json:"backup_dir"`
}

func Paths(storeDir string) StorePaths {
	return StorePaths{
		StoreDir:        storeDir,
		DictionaryStore: filepath.Join(storeDir, "dictionary.store"),
		SnippetsStore:   filepath.Join(storeDir, "snippets.store"),
	}
}

func Status(ctx context.Context, storeDir string, running bool) (StoreStatus, []report.Diagnostic, error) {
	paths := Paths(storeDir)
	if diagnostics := requireStores(paths); len(diagnostics) > 0 {
		return StoreStatus{
			StoreDir:             paths.StoreDir,
			DictionaryStore:      paths.DictionaryStore,
			SnippetsStore:        paths.SnippetsStore,
			TypeWhisperRunning:   running,
			DictionaryStoreFound: fileExists(paths.DictionaryStore),
			SnippetsStoreFound:   fileExists(paths.SnippetsStore),
		}, diagnostics, errors.New("missing TypeWhisper stores")
	}
	dictionary, err := sql.Open("sqlite", paths.DictionaryStore)
	if err != nil {
		return StoreStatus{}, nil, err
	}
	defer dictionary.Close()
	snippets, err := sql.Open("sqlite", paths.SnippetsStore)
	if err != nil {
		return StoreStatus{}, nil, err
	}
	defer snippets.Close()

	termCount, err := countRows(ctx, dictionary, "select count(*) from ZDICTIONARYENTRY where ZENTRYTYPE = 'term'")
	if err != nil {
		return StoreStatus{}, storeReadDiagnostic(paths.DictionaryStore, err), err
	}
	correctionCount, err := countRows(ctx, dictionary, "select count(*) from ZDICTIONARYENTRY where ZENTRYTYPE = 'correction'")
	if err != nil {
		return StoreStatus{}, storeReadDiagnostic(paths.DictionaryStore, err), err
	}
	snippetCount, err := countRows(ctx, snippets, "select count(*) from ZSNIPPET")
	if err != nil {
		return StoreStatus{}, storeReadDiagnostic(paths.SnippetsStore, err), err
	}
	return StoreStatus{
		StoreDir:             paths.StoreDir,
		DictionaryStore:      paths.DictionaryStore,
		SnippetsStore:        paths.SnippetsStore,
		Terms:                termCount,
		Corrections:          correctionCount,
		Snippets:             snippetCount,
		TypeWhisperRunning:   running,
		DictionaryStoreFound: true,
		SnippetsStoreFound:   true,
	}, nil, nil
}

func Export(ctx context.Context, storeDir string) (Lexicon, []report.Diagnostic, error) {
	paths := Paths(storeDir)
	if diagnostics := requireStores(paths); len(diagnostics) > 0 {
		return Lexicon{}, diagnostics, errors.New("missing TypeWhisper stores")
	}
	dictionary, err := sql.Open("sqlite", paths.DictionaryStore)
	if err != nil {
		return Lexicon{}, storeReadDiagnostic(paths.DictionaryStore, err), err
	}
	defer dictionary.Close()
	snippets, err := sql.Open("sqlite", paths.SnippetsStore)
	if err != nil {
		return Lexicon{}, storeReadDiagnostic(paths.SnippetsStore, err), err
	}
	defer snippets.Close()

	terms, corrections, err := exportDictionary(ctx, dictionary)
	if err != nil {
		return Lexicon{}, storeReadDiagnostic(paths.DictionaryStore, err), err
	}
	exportedSnippets, err := exportSnippets(ctx, snippets)
	if err != nil {
		return Lexicon{}, storeReadDiagnostic(paths.SnippetsStore, err), err
	}
	return Lexicon{
		Version: 1,
		Dictionary: Dictionary{
			Terms:       terms,
			Corrections: corrections,
		},
		Snippets: exportedSnippets,
	}, nil, nil
}

func PlanImport(ctx context.Context, lexicon Lexicon, storeDir string, running bool) (ImportPlan, []report.Diagnostic, error) {
	paths := Paths(storeDir)
	if diagnostics := requireStores(paths); len(diagnostics) > 0 {
		return ImportPlan{}, diagnostics, errors.New("missing TypeWhisper stores")
	}
	dictionary, err := sql.Open("sqlite", paths.DictionaryStore)
	if err != nil {
		return ImportPlan{}, storeReadDiagnostic(paths.DictionaryStore, err), err
	}
	defer dictionary.Close()
	snippets, err := sql.Open("sqlite", paths.SnippetsStore)
	if err != nil {
		return ImportPlan{}, storeReadDiagnostic(paths.SnippetsStore, err), err
	}
	defer snippets.Close()

	dictionaryCounts, err := dictionaryChangeCounts(ctx, dictionary, lexicon)
	if err != nil {
		return ImportPlan{}, storeReadDiagnostic(paths.DictionaryStore, err), err
	}
	snippetCounts, err := snippetsChangeCounts(ctx, snippets, lexicon)
	if err != nil {
		return ImportPlan{}, storeReadDiagnostic(paths.SnippetsStore, err), err
	}
	return ImportPlan{
		Lexicon:            lexicon.Summary(),
		Dictionary:         dictionaryCounts,
		Snippets:           snippetCounts,
		TypeWhisperRunning: running,
	}, nil, nil
}

func ApplyImport(ctx context.Context, lexicon Lexicon, storeDir string, repoRoot string, now time.Time, running bool) (ImportResult, []report.Diagnostic, error) {
	plan, diagnostics, err := PlanImport(ctx, lexicon, storeDir, running)
	if err != nil {
		return ImportResult{}, diagnostics, err
	}
	backupDir, err := BackupStores(storeDir, repoRoot, now)
	if err != nil {
		return ImportResult{}, []report.Diagnostic{{
			Severity: "error",
			Code:     "typewhisper.backup_failed",
			Message:  err.Error(),
			Path:     storeDir,
		}}, err
	}
	paths := Paths(storeDir)
	dictionary, err := sql.Open("sqlite", paths.DictionaryStore)
	if err != nil {
		return ImportResult{}, storeReadDiagnostic(paths.DictionaryStore, err), err
	}
	defer dictionary.Close()
	snippets, err := sql.Open("sqlite", paths.SnippetsStore)
	if err != nil {
		return ImportResult{}, storeReadDiagnostic(paths.SnippetsStore, err), err
	}
	defer snippets.Close()

	if err := applyDictionary(ctx, dictionary, lexicon); err != nil {
		return ImportResult{}, storeWriteDiagnostic(paths.DictionaryStore, err), err
	}
	if err := applySnippets(ctx, snippets, lexicon); err != nil {
		return ImportResult{}, storeWriteDiagnostic(paths.SnippetsStore, err), err
	}
	return ImportResult{Plan: plan, BackupDir: backupDir}, nil, nil
}

func PlanChanged(plan ImportPlan) bool {
	return plan.Dictionary.Updates+plan.Dictionary.Insertions+plan.Snippets.Updates+plan.Snippets.Insertions > 0
}

func countRows(ctx context.Context, db *sql.DB, query string) (int, error) {
	var count int
	if err := db.QueryRowContext(ctx, query).Scan(&count); err != nil {
		return 0, err
	}
	return count, nil
}

func exportDictionary(ctx context.Context, db *sql.DB) ([]Term, []Correction, error) {
	termRows, err := db.QueryContext(ctx, `select ZORIGINAL, ZCASESENSITIVE, ZISENABLED from ZDICTIONARYENTRY where ZENTRYTYPE = 'term' order by lower(ZORIGINAL)`)
	if err != nil {
		return nil, nil, err
	}
	defer termRows.Close()
	var terms []Term
	for termRows.Next() {
		var term Term
		var caseSensitive, isEnabled int
		if err := termRows.Scan(&term.Original, &caseSensitive, &isEnabled); err != nil {
			return nil, nil, err
		}
		term.CaseSensitive = caseSensitive != 0
		term.IsEnabled = isEnabled != 0
		terms = append(terms, term)
	}
	if err := termRows.Err(); err != nil {
		return nil, nil, err
	}

	correctionRows, err := db.QueryContext(ctx, `select ZORIGINAL, coalesce(ZREPLACEMENT, ''), ZCASESENSITIVE, ZISENABLED from ZDICTIONARYENTRY where ZENTRYTYPE = 'correction' order by lower(ZORIGINAL)`)
	if err != nil {
		return nil, nil, err
	}
	defer correctionRows.Close()
	var corrections []Correction
	for correctionRows.Next() {
		var correction Correction
		var caseSensitive, isEnabled int
		if err := correctionRows.Scan(&correction.Original, &correction.Replacement, &caseSensitive, &isEnabled); err != nil {
			return nil, nil, err
		}
		correction.CaseSensitive = caseSensitive != 0
		correction.IsEnabled = isEnabled != 0
		correction.replacementSet = true
		corrections = append(corrections, correction)
	}
	if err := correctionRows.Err(); err != nil {
		return nil, nil, err
	}
	return terms, corrections, nil
}

func exportSnippets(ctx context.Context, db *sql.DB) ([]Snippet, error) {
	rows, err := db.QueryContext(ctx, `select ZTRIGGER, coalesce(ZREPLACEMENT, ''), ZCASESENSITIVE, ZISENABLED from ZSNIPPET order by ZTRIGGER`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var snippets []Snippet
	for rows.Next() {
		var snippet Snippet
		var caseSensitive, isEnabled int
		if err := rows.Scan(&snippet.Trigger, &snippet.Replacement, &caseSensitive, &isEnabled); err != nil {
			return nil, err
		}
		snippet.CaseSensitive = caseSensitive != 0
		snippet.IsEnabled = isEnabled != 0
		snippet.replacementSet = true
		snippets = append(snippets, snippet)
	}
	return snippets, rows.Err()
}

func dictionaryChangeCounts(ctx context.Context, db *sql.DB, lexicon Lexicon) (ChangeCounts, error) {
	existing, err := existingDictionaryKeys(ctx, db)
	if err != nil {
		return ChangeCounts{}, err
	}
	var counts ChangeCounts
	for _, term := range lexicon.Dictionary.Terms {
		if existing["term|"+strings.ToLower(term.Original)] {
			counts.Updates++
		} else {
			counts.Insertions++
		}
	}
	for _, correction := range lexicon.Dictionary.Corrections {
		if existing["correction|"+strings.ToLower(correction.Original)] {
			counts.Updates++
		} else {
			counts.Insertions++
		}
	}
	return counts, nil
}

func snippetsChangeCounts(ctx context.Context, db *sql.DB, lexicon Lexicon) (ChangeCounts, error) {
	existing, err := existingSnippetKeys(ctx, db)
	if err != nil {
		return ChangeCounts{}, err
	}
	var counts ChangeCounts
	for _, snippet := range lexicon.Snippets {
		if existing[snippet.Trigger] {
			counts.Updates++
		} else {
			counts.Insertions++
		}
	}
	return counts, nil
}

func existingDictionaryKeys(ctx context.Context, db *sql.DB) (map[string]bool, error) {
	rows, err := db.QueryContext(ctx, `select ZENTRYTYPE, ZORIGINAL from ZDICTIONARYENTRY where ZENTRYTYPE in ('term', 'correction')`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	keys := make(map[string]bool)
	for rows.Next() {
		var entryType, original string
		if err := rows.Scan(&entryType, &original); err != nil {
			return nil, err
		}
		keys[entryType+"|"+strings.ToLower(strings.TrimSpace(original))] = true
	}
	return keys, rows.Err()
}

func existingSnippetKeys(ctx context.Context, db *sql.DB) (map[string]bool, error) {
	rows, err := db.QueryContext(ctx, `select ZTRIGGER from ZSNIPPET`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	keys := make(map[string]bool)
	for rows.Next() {
		var trigger string
		if err := rows.Scan(&trigger); err != nil {
			return nil, err
		}
		keys[strings.TrimSpace(trigger)] = true
	}
	return keys, rows.Err()
}

func applyDictionary(ctx context.Context, db *sql.DB, lexicon Lexicon) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for _, term := range lexicon.Dictionary.Terms {
		if err := upsertDictionaryEntry(ctx, tx, "term", term.Original, nil, term.CaseSensitive, term.IsEnabled); err != nil {
			return err
		}
	}
	for _, correction := range lexicon.Dictionary.Corrections {
		replacement := correction.Replacement
		if err := upsertDictionaryEntry(ctx, tx, "correction", correction.Original, &replacement, correction.CaseSensitive, correction.IsEnabled); err != nil {
			return err
		}
	}
	if _, err := tx.ExecContext(ctx, `update Z_PRIMARYKEY set Z_MAX = coalesce((select max(Z_PK) from ZDICTIONARYENTRY), 0) where Z_NAME = 'DictionaryEntry'`); err != nil {
		return err
	}
	return tx.Commit()
}

func upsertDictionaryEntry(ctx context.Context, tx *sql.Tx, entryType string, original string, replacement *string, caseSensitive bool, isEnabled bool) error {
	result, err := tx.ExecContext(ctx, `
update ZDICTIONARYENTRY
set ZORIGINAL = ?, ZREPLACEMENT = ?, ZCASESENSITIVE = ?, ZISENABLED = ?, Z_OPT = Z_OPT + 1
where ZENTRYTYPE = ? and lower(ZORIGINAL) = lower(?)`,
		original, replacement, boolInt(caseSensitive), boolInt(isEnabled), entryType, original)
	if err != nil {
		return err
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if affected > 0 {
		return nil
	}
	_, err = tx.ExecContext(ctx, `
insert into ZDICTIONARYENTRY (
  Z_ENT, Z_OPT, ZCASESENSITIVE, ZISENABLED, ZUSAGECOUNT, ZCREATEDAT,
  ZENTRYTYPE, ZORIGINAL, ZREPLACEMENT, ZID
) values (
  1, 1, ?, ?, 0,
  (julianday('now') - julianday('2001-01-01 00:00:00')) * 86400.0,
  ?, ?, ?, randomblob(16)
)`, boolInt(caseSensitive), boolInt(isEnabled), entryType, original, replacement)
	return err
}

func applySnippets(ctx context.Context, db *sql.DB, lexicon Lexicon) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for _, snippet := range lexicon.Snippets {
		if err := upsertSnippet(ctx, tx, snippet); err != nil {
			return err
		}
	}
	if _, err := tx.ExecContext(ctx, `update Z_PRIMARYKEY set Z_MAX = coalesce((select max(Z_PK) from ZSNIPPET), 0) where Z_NAME = 'Snippet'`); err != nil {
		return err
	}
	return tx.Commit()
}

func upsertSnippet(ctx context.Context, tx *sql.Tx, snippet Snippet) error {
	result, err := tx.ExecContext(ctx, `
update ZSNIPPET
set ZTRIGGER = ?, ZREPLACEMENT = ?, ZCASESENSITIVE = ?, ZISENABLED = ?, Z_OPT = Z_OPT + 1
where ZTRIGGER = ?`,
		snippet.Trigger, snippet.Replacement, boolInt(snippet.CaseSensitive), boolInt(snippet.IsEnabled), snippet.Trigger)
	if err != nil {
		return err
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if affected > 0 {
		return nil
	}
	_, err = tx.ExecContext(ctx, `
insert into ZSNIPPET (
  Z_ENT, Z_OPT, ZCASESENSITIVE, ZISENABLED, ZUSAGECOUNT, ZCREATEDAT,
  ZREPLACEMENT, ZTRIGGER, ZID
) values (
  1, 1, ?, ?, 0,
  (julianday('now') - julianday('2001-01-01 00:00:00')) * 86400.0,
  ?, ?, randomblob(16)
)`, boolInt(snippet.CaseSensitive), boolInt(snippet.IsEnabled), snippet.Replacement, snippet.Trigger)
	return err
}

func requireStores(paths StorePaths) []report.Diagnostic {
	var diagnostics []report.Diagnostic
	if !fileExists(paths.DictionaryStore) {
		diagnostics = append(diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "typewhisper.dictionary_store_missing",
			Message:  "dictionary store not found",
			Path:     paths.DictionaryStore,
		})
	}
	if !fileExists(paths.SnippetsStore) {
		diagnostics = append(diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "typewhisper.snippets_store_missing",
			Message:  "snippets store not found",
			Path:     paths.SnippetsStore,
		})
	}
	return diagnostics
}

func storeReadDiagnostic(path string, err error) []report.Diagnostic {
	return []report.Diagnostic{{
		Severity: "error",
		Code:     "typewhisper.store_read_failed",
		Message:  err.Error(),
		Path:     path,
	}}
}

func storeWriteDiagnostic(path string, err error) []report.Diagnostic {
	return []report.Diagnostic{{
		Severity: "error",
		Code:     "typewhisper.store_write_failed",
		Message:  err.Error(),
		Path:     path,
	}}
}

func boolInt(value bool) int {
	if value {
		return 1
	}
	return 0
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}
