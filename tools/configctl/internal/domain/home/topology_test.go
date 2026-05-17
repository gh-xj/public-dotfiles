package home

import (
	"os"
	"path/filepath"
	"testing"
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
