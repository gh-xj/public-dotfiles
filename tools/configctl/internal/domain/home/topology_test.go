package home

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestStatusDetectsLinkedAndMissingEntries(t *testing.T) {
	root := t.TempDir()
	homeDir := filepath.Join(root, "home")
	publicRepo := filepath.Join(root, "public-dotfiles")
	privateRepo := filepath.Join(root, "private-config")
	writeFile(t, filepath.Join(publicRepo, "configctl", "home.toml"), `[[entries]]
owner = "public"
path = ".zshrc"
mode = "link"

[[entries]]
owner = "public"
path = ".codex/config.toml"
mode = "merge"
strategy = "codex-top-level-keys"
`)
	writeFile(t, filepath.Join(privateRepo, "configctl", "home.toml"), `[[entries]]
owner = "private"
path = ".zshenv"
mode = "link"
`)
	writeFile(t, filepath.Join(publicRepo, ".zshrc"), "source\n")
	writeFile(t, filepath.Join(publicRepo, ".codex", "config.toml"), "model = \"x\"\n")
	writeFile(t, filepath.Join(privateRepo, ".zshenv"), "private\n")
	mkdir(t, filepath.Join(homeDir, ".zshrc"))
	remove(t, filepath.Join(homeDir, ".zshrc"))
	if err := os.Symlink(filepath.Join(publicRepo, ".zshrc"), filepath.Join(homeDir, ".zshrc")); err != nil {
		t.Fatal(err)
	}

	status, err := Status(Options{HomeDir: homeDir, PublicRepoDir: publicRepo, PrivateRepoDir: privateRepo})
	if err != nil {
		t.Fatal(err)
	}
	if status.Counts["linked"] != 1 {
		t.Fatalf("expected one linked entry, got %#v", status.Counts)
	}
	if status.Counts["missing"] != 2 {
		t.Fatalf("expected two missing entries, got %#v", status.Counts)
	}
}

func TestVerifyFailsWrongLink(t *testing.T) {
	root := t.TempDir()
	homeDir := filepath.Join(root, "home")
	publicRepo := filepath.Join(root, "public-dotfiles")
	writeFile(t, filepath.Join(publicRepo, "configctl", "home.toml"), `[[entries]]
owner = "public"
path = ".zshrc"
mode = "link"
`)
	writeFile(t, filepath.Join(publicRepo, ".zshrc"), "source\n")
	writeFile(t, filepath.Join(root, "other", ".zshrc"), "wrong\n")
	mkdir(t, homeDir)
	if err := os.Symlink(filepath.Join(root, "other", ".zshrc"), filepath.Join(homeDir, ".zshrc")); err != nil {
		t.Fatal(err)
	}

	_, failures, err := Verify(Options{HomeDir: homeDir, PublicRepoDir: publicRepo, PublicOnly: true})
	if err != nil {
		t.Fatal(err)
	}
	if len(failures) != 1 {
		t.Fatalf("expected one failure, got %#v", failures)
	}
	if failures[0].Code != "home.verify.link_not_owned" {
		t.Fatalf("unexpected failure: %#v", failures[0])
	}
}

func TestVerifyDefaultUsesRepresentativeScope(t *testing.T) {
	root := t.TempDir()
	homeDir := filepath.Join(root, "home")
	publicRepo := filepath.Join(root, "public-dotfiles")
	writeFile(t, filepath.Join(publicRepo, "configctl", "home.toml"), `[[entries]]
owner = "public"
path = ".zshrc"
mode = "link"

[[entries]]
owner = "public"
path = ".hushlogin"
mode = "link"
`)
	writeFile(t, filepath.Join(publicRepo, ".zshrc"), "source\n")
	writeFile(t, filepath.Join(publicRepo, ".hushlogin"), "source\n")
	mkdir(t, homeDir)
	if err := os.Symlink(filepath.Join(publicRepo, ".zshrc"), filepath.Join(homeDir, ".zshrc")); err != nil {
		t.Fatal(err)
	}

	status, failures, err := Verify(Options{HomeDir: homeDir, PublicRepoDir: publicRepo, PublicOnly: true})
	if err != nil {
		t.Fatal(err)
	}
	if len(failures) != 0 {
		t.Fatalf("expected default verify to ignore non-representative drift, got %#v", failures)
	}
	if len(status.Entries) != 1 {
		t.Fatalf("expected one representative entry, got %#v", status.Entries)
	}

	allStatus, allFailures, err := Verify(Options{HomeDir: homeDir, PublicRepoDir: publicRepo, PublicOnly: true, VerifyAll: true})
	if err != nil {
		t.Fatal(err)
	}
	if len(allStatus.Entries) != 2 {
		t.Fatalf("expected full verify to inspect both entries, got %#v", allStatus.Entries)
	}
	if len(allFailures) != 1 {
		t.Fatalf("expected full verify to catch non-representative drift, got %#v", allFailures)
	}
}

func TestLoadManifestFailsClosedOnInvalidEntries(t *testing.T) {
	root := t.TempDir()
	publicRepo := filepath.Join(root, "public-dotfiles")
	writeFile(t, filepath.Join(publicRepo, "configctl", "home.toml"), `[[entries]]
owner = "private"
path = ".zshrc"
mode = "link"
`)
	writeFile(t, filepath.Join(publicRepo, ".zshrc"), "source\n")

	_, diagnostics, err := LoadManifest("public", publicRepo)
	if err == nil {
		t.Fatal("expected invalid manifest to fail")
	}
	if len(diagnostics) != 1 || diagnostics[0].Code != "home.manifest.owner_mismatch" {
		t.Fatalf("unexpected diagnostics: %#v", diagnostics)
	}
}

func TestApplyLinksMissingPathAndBacksUpWrongLink(t *testing.T) {
	root := t.TempDir()
	homeDir := filepath.Join(root, "home")
	publicRepo := filepath.Join(root, "public-dotfiles")
	writeFile(t, filepath.Join(publicRepo, "configctl", "home.toml"), `[[entries]]
owner = "public"
path = ".zshrc"
mode = "link"

[[entries]]
owner = "public"
path = ".tmux.conf"
mode = "link"
`)
	writeFile(t, filepath.Join(publicRepo, ".zshrc"), "source\n")
	writeFile(t, filepath.Join(publicRepo, ".tmux.conf"), "tmux\n")
	writeFile(t, filepath.Join(root, "other", ".tmux.conf"), "wrong\n")
	mkdir(t, homeDir)
	if err := os.Symlink(filepath.Join(root, "other", ".tmux.conf"), filepath.Join(homeDir, ".tmux.conf")); err != nil {
		t.Fatal(err)
	}

	result, err := Apply(Options{
		HomeDir:       homeDir,
		PublicRepoDir: publicRepo,
		PublicOnly:    true,
		Now:           time.Date(2026, 5, 17, 1, 2, 3, 0, time.UTC),
	})
	if err != nil {
		t.Fatalf("Apply returned error: %v diagnostics=%#v", err, result.Diagnostics)
	}
	if !result.Changed {
		t.Fatal("expected apply to report changes")
	}
	assertSymlink(t, filepath.Join(homeDir, ".zshrc"), filepath.Join(publicRepo, ".zshrc"))
	assertSymlink(t, filepath.Join(homeDir, ".tmux.conf"), filepath.Join(publicRepo, ".tmux.conf"))
	if _, err := os.Lstat(filepath.Join(publicRepo, ".install-backups", "20260517-010203", ".tmux.conf")); err != nil {
		t.Fatalf("expected backup: %v", err)
	}
}

func TestApplyDryRunDoesNotMutate(t *testing.T) {
	root := t.TempDir()
	homeDir := filepath.Join(root, "home")
	publicRepo := filepath.Join(root, "public-dotfiles")
	writeFile(t, filepath.Join(publicRepo, "configctl", "home.toml"), `[[entries]]
owner = "public"
path = ".zshrc"
mode = "link"
`)
	writeFile(t, filepath.Join(publicRepo, ".zshrc"), "source\n")
	mkdir(t, homeDir)

	result, err := Apply(Options{HomeDir: homeDir, PublicRepoDir: publicRepo, PublicOnly: true, DryRun: true})
	if err != nil {
		t.Fatalf("Apply returned error: %v diagnostics=%#v", err, result.Diagnostics)
	}
	if !result.Changed {
		t.Fatal("expected dry run to report planned changes")
	}
	if _, err := os.Lstat(filepath.Join(homeDir, ".zshrc")); !os.IsNotExist(err) {
		t.Fatalf("dry run should not create target, err=%v", err)
	}
}

func TestApplyMergeCodexTopLevelKeysBacksUpInResolvedPrivateRepo(t *testing.T) {
	root := t.TempDir()
	homeDir := filepath.Join(root, "home")
	publicRepo := filepath.Join(root, "public-dotfiles")
	privateRepo := filepath.Join(root, "private-config")
	writeFile(t, filepath.Join(publicRepo, "configctl", "home.toml"), `[[entries]]
owner = "public"
path = ".codex/config.toml"
mode = "merge"
strategy = "codex-top-level-keys"
`)
	writeFile(t, filepath.Join(publicRepo, ".codex", "config.toml"), "model = \"gpt\"\n\n[tui]\ntheme = \"dark\"\n")
	writeFile(t, filepath.Join(privateRepo, ".codex", "config.toml"), "\n[projects]\n")
	mkdir(t, homeDir)
	if err := os.Symlink(filepath.Join(privateRepo, ".codex"), filepath.Join(homeDir, ".codex")); err != nil {
		t.Fatal(err)
	}

	result, err := Apply(Options{
		HomeDir:        homeDir,
		PublicRepoDir:  publicRepo,
		PrivateRepoDir: privateRepo,
		PublicOnly:     true,
		Now:            time.Date(2026, 5, 17, 1, 2, 3, 0, time.UTC),
	})
	if err != nil {
		t.Fatalf("Apply returned error: %v diagnostics=%#v", err, result.Diagnostics)
	}
	content, err := os.ReadFile(filepath.Join(privateRepo, ".codex", "config.toml"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(string(content), "model = \"gpt\"\n\n[projects]\n") {
		t.Fatalf("unexpected merged content: %q", content)
	}
	if _, err := os.Stat(filepath.Join(privateRepo, ".install-backups", "20260517-010203", ".codex", "config.toml")); err != nil {
		t.Fatalf("expected private backup: %v", err)
	}
}

func TestPrivateOnlyLoadsPrivateManifestOnly(t *testing.T) {
	root := t.TempDir()
	homeDir := filepath.Join(root, "home")
	publicRepo := filepath.Join(root, "public-dotfiles")
	privateRepo := filepath.Join(root, "private-config")
	writeFile(t, filepath.Join(publicRepo, "configctl", "home.toml"), `[[entries]]
owner = "public"
path = ".zshrc"
mode = "link"
`)
	writeFile(t, filepath.Join(privateRepo, "configctl", "home.toml"), `[[entries]]
owner = "private"
path = ".zshenv"
mode = "link"
`)
	writeFile(t, filepath.Join(publicRepo, ".zshrc"), "source\n")
	writeFile(t, filepath.Join(privateRepo, ".zshenv"), "private\n")

	status, err := Status(Options{HomeDir: homeDir, PublicRepoDir: publicRepo, PrivateRepoDir: privateRepo, PrivateOnly: true})
	if err != nil {
		t.Fatal(err)
	}
	if len(status.Entries) != 1 || status.Entries[0].Owner != "private" {
		t.Fatalf("expected private-only status, got %#v", status.Entries)
	}
}

func TestResolveMatchesManifestEntry(t *testing.T) {
	root := t.TempDir()
	homeDir := filepath.Join(root, "home")
	publicRepo := filepath.Join(root, "public-dotfiles")
	writeFile(t, filepath.Join(publicRepo, "configctl", "home.toml"), `[[entries]]
owner = "public"
path = ".zshrc"
mode = "link"
`)
	writeFile(t, filepath.Join(publicRepo, ".zshrc"), "source\n")
	mkdir(t, homeDir)
	if err := os.Symlink(filepath.Join(publicRepo, ".zshrc"), filepath.Join(homeDir, ".zshrc")); err != nil {
		t.Fatal(err)
	}

	result, err := Resolve(".zshrc", Options{HomeDir: homeDir, PublicRepoDir: publicRepo, PublicOnly: true})
	if err != nil {
		t.Fatal(err)
	}
	if result.Owner != "public" {
		t.Fatalf("expected public owner, got %#v", result)
	}
	if result.Entry == nil || result.Entry.Path != ".zshrc" {
		t.Fatalf("expected manifest entry, got %#v", result.Entry)
	}
}

func assertSymlink(t *testing.T, path string, want string) {
	t.Helper()
	got, err := os.Readlink(path)
	if err != nil {
		t.Fatal(err)
	}
	if got != want {
		t.Fatalf("expected %s -> %s, got %s", path, want, got)
	}
}

func writeFile(t *testing.T, path string, content string) {
	t.Helper()
	mkdir(t, filepath.Dir(path))
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func mkdir(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(path, 0o755); err != nil {
		t.Fatal(err)
	}
}

func remove(t *testing.T, path string) {
	t.Helper()
	if err := os.RemoveAll(path); err != nil {
		t.Fatal(err)
	}
}
