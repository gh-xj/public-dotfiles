package packageaudit

import (
	"os"
	"path/filepath"
	"testing"
)

func TestParseLedgersSkipsCommentsAndCountsPackages(t *testing.T) {
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "Brewfile"), `# comment
tap "homebrew/bundle"
brew "gh"
brew "git-delta", restart_service: true
cask "ghostty"
`)
	writeFile(t, filepath.Join(root, "npm-globals.txt"), `# comment
@openai/codex
typescript
`)

	ledger := loadLedgers(Options{PublicRepoDir: root})[0]
	if got := len(ledger.Brew.Taps); got != 1 {
		t.Fatalf("brew taps = %d, want 1", got)
	}
	if got := len(ledger.Brew.Formulae); got != 2 {
		t.Fatalf("brew formulae = %d, want 2", got)
	}
	if got := len(ledger.Brew.Casks); got != 1 {
		t.Fatalf("brew casks = %d, want 1", got)
	}
	if got := len(ledger.NPM.Packages); got != 2 {
		t.Fatalf("npm packages = %d, want 2", got)
	}
}

func TestAuditReportsMissingDuplicateUntrackedAndConfigWithoutLedger(t *testing.T) {
	publicRoot := t.TempDir()
	privateRoot := t.TempDir()
	writeFile(t, filepath.Join(publicRoot, "Brewfile"), `brew "gh"
cask "ghostty"
`)
	writeFile(t, filepath.Join(publicRoot, "npm-globals.txt"), `@openai/codex
`)
	writeFile(t, filepath.Join(privateRoot, "Brewfile"), `brew "gh"
`)
	writeFile(t, filepath.Join(privateRoot, "npm-globals.txt"), "")
	writeFile(t, filepath.Join(publicRoot, ".config", "nvim", "init.lua"), "return {}\n")

	ledgers := loadLedgers(Options{PublicRepoDir: publicRoot, PrivateRepoDir: privateRoot})
	result := audit(Options{PublicRepoDir: publicRoot, PrivateRepoDir: privateRoot}, ledgers, InstalledStatus{
		Brew: BrewInstalled{
			Available:         true,
			Formulae:          []string{"gh", "lazygit"},
			RequestedFormulae: []string{"gh", "lazygit"},
			Casks:             []string{},
		},
		NPM: NPMInstalled{
			Available: true,
			Packages:  []string{"@openai/codex", "typescript"},
		},
	})

	if got := result.Counts["tracked_missing"]; got != 1 {
		t.Fatalf("tracked_missing = %d, want 1", got)
	}
	if got := result.Counts["installed_untracked"]; got != 2 {
		t.Fatalf("installed_untracked = %d, want 2", got)
	}
	if got := result.Counts["duplicated"]; got != 1 {
		t.Fatalf("duplicated = %d, want 1", got)
	}
	if got := result.Counts["config_without_package_ledger_support"]; got != 1 {
		t.Fatalf("config_without_package_ledger_support = %d, want 1", got)
	}
}

func writeFile(t *testing.T, path string, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}
