package repo

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadRegistryResolvesRelativePathsAndSkipsMissingOverlay(t *testing.T) {
	root := t.TempDir()
	registryPath := filepath.Join(root, "public-dotfiles", "configctl", "repos.toml")
	writeFile(t, registryPath, `schema_version = "configctl.repos.v1"
private_overlay = "../../private-config/configctl/repos.local.toml"

[[repos]]
name = "public-dotfiles"
owner = "public"
path = ".."
required = true

[[repos]]
name = "private-config"
owner = "private"
path = "../../private-config"
required = false
`)

	registry, diagnostics, err := LoadRegistry(registryPath)
	if err != nil {
		t.Fatalf("LoadRegistry returned error: %v diagnostics=%#v", err, diagnostics)
	}
	if registry.Overlay.Exists {
		t.Fatal("missing overlay should not be required")
	}
	if len(registry.Repos) != 2 {
		t.Fatalf("repos = %#v, want 2", registry.Repos)
	}
	wantPublic := filepath.Join(root, "public-dotfiles")
	if registry.Repos[0].Path != wantPublic {
		t.Fatalf("public path = %q, want %q", registry.Repos[0].Path, wantPublic)
	}
}

func TestLoadRegistryAppliesPrivateOverlay(t *testing.T) {
	root := t.TempDir()
	registryPath := filepath.Join(root, "public-dotfiles", "configctl", "repos.toml")
	privatePath := filepath.Join(root, "machine", "private-config")
	writeFile(t, registryPath, `schema_version = "configctl.repos.v1"
private_overlay = "../../private-config/configctl/repos.local.toml"

[[repos]]
name = "private-config"
owner = "private"
path = "../../private-config"
required = false
`)
	writeFile(t, filepath.Join(root, "private-config", "configctl", "repos.local.toml"), `schema_version = "configctl.repos.overlay.v1"

[[repos]]
name = "private-config"
path = "../../machine/private-config"
required = true
`)

	registry, diagnostics, err := LoadRegistry(registryPath)
	if err != nil {
		t.Fatalf("LoadRegistry returned error: %v diagnostics=%#v", err, diagnostics)
	}
	if !registry.Overlay.Exists {
		t.Fatal("expected overlay to be loaded")
	}
	if len(registry.Repos) != 1 {
		t.Fatalf("repos = %#v, want 1", registry.Repos)
	}
	if registry.Repos[0].Path != privatePath {
		t.Fatalf("private path = %q, want %q", registry.Repos[0].Path, privatePath)
	}
	if !registry.Repos[0].Required {
		t.Fatal("overlay should override required")
	}
	if registry.Repos[0].Owner != "private" {
		t.Fatalf("owner = %q, want private", registry.Repos[0].Owner)
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
