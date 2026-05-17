package typewhisper

import (
	"context"
	"database/sql"
	"path/filepath"
	"testing"
	"time"
)

func TestPlanAndApplyImport(t *testing.T) {
	ctx := context.Background()
	storeDir := t.TempDir()
	createTestStores(t, storeDir)

	lexicon := Lexicon{
		Version: 1,
		Dictionary: Dictionary{
			Terms: []Term{
				{Original: "codex", IsEnabled: true},
				{Original: "TypeWhisper", CaseSensitive: true, IsEnabled: true},
			},
			Corrections: []Correction{
				{Original: "codexx", Replacement: "codex", IsEnabled: true, replacementSet: true},
			},
		},
		Snippets: []Snippet{
			{Trigger: ";sig", Replacement: "xj", IsEnabled: true, replacementSet: true},
		},
	}

	plan, diagnostics, err := PlanImport(ctx, lexicon, storeDir, false)
	if err != nil {
		t.Fatalf("PlanImport returned error: %v diagnostics=%#v", err, diagnostics)
	}
	if plan.Dictionary.Updates != 1 || plan.Dictionary.Insertions != 2 {
		t.Fatalf("unexpected dictionary plan: %#v", plan.Dictionary)
	}
	if plan.Snippets.Updates != 0 || plan.Snippets.Insertions != 1 {
		t.Fatalf("unexpected snippet plan: %#v", plan.Snippets)
	}

	result, diagnostics, err := ApplyImport(ctx, lexicon, storeDir, t.TempDir(), time.Date(2026, 5, 17, 1, 2, 3, 0, time.UTC), false)
	if err != nil {
		t.Fatalf("ApplyImport returned error: %v diagnostics=%#v", err, diagnostics)
	}
	if result.BackupDir == "" {
		t.Fatal("expected backup dir")
	}

	status, diagnostics, err := Status(ctx, storeDir, false)
	if err != nil {
		t.Fatalf("Status returned error: %v diagnostics=%#v", err, diagnostics)
	}
	if status.Terms != 2 || status.Corrections != 1 || status.Snippets != 1 {
		t.Fatalf("unexpected status: %#v", status)
	}
}

func createTestStores(t *testing.T, storeDir string) {
	t.Helper()
	dictionary, err := sql.Open("sqlite", filepath.Join(storeDir, "dictionary.store"))
	if err != nil {
		t.Fatal(err)
	}
	defer dictionary.Close()
	if _, err := dictionary.Exec(`
create table ZDICTIONARYENTRY (
  Z_PK integer primary key autoincrement,
  Z_ENT integer,
  Z_OPT integer,
  ZCASESENSITIVE integer,
  ZISENABLED integer,
  ZUSAGECOUNT integer,
  ZCREATEDAT timestamp,
  ZENTRYTYPE varchar,
  ZORIGINAL varchar,
  ZREPLACEMENT varchar,
  ZID blob
);
create table Z_PRIMARYKEY (Z_ENT integer primary key, Z_NAME varchar, Z_SUPER integer, Z_MAX integer);
insert into Z_PRIMARYKEY (Z_ENT, Z_NAME, Z_SUPER, Z_MAX) values (1, 'DictionaryEntry', 0, 1);
insert into ZDICTIONARYENTRY (Z_ENT, Z_OPT, ZCASESENSITIVE, ZISENABLED, ZUSAGECOUNT, ZCREATEDAT, ZENTRYTYPE, ZORIGINAL, ZREPLACEMENT, ZID)
values (1, 1, 0, 1, 0, 0, 'term', 'codex', null, randomblob(16));
`); err != nil {
		t.Fatal(err)
	}

	snippets, err := sql.Open("sqlite", filepath.Join(storeDir, "snippets.store"))
	if err != nil {
		t.Fatal(err)
	}
	defer snippets.Close()
	if _, err := snippets.Exec(`
create table ZSNIPPET (
  Z_PK integer primary key autoincrement,
  Z_ENT integer,
  Z_OPT integer,
  ZCASESENSITIVE integer,
  ZISENABLED integer,
  ZUSAGECOUNT integer,
  ZCREATEDAT timestamp,
  ZREPLACEMENT varchar,
  ZTRIGGER varchar,
  ZID blob
);
create table Z_PRIMARYKEY (Z_ENT integer primary key, Z_NAME varchar, Z_SUPER integer, Z_MAX integer);
insert into Z_PRIMARYKEY (Z_ENT, Z_NAME, Z_SUPER, Z_MAX) values (1, 'Snippet', 0, 0);
`); err != nil {
		t.Fatal(err)
	}
}
