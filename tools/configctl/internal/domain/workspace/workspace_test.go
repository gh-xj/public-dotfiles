package workspace

import (
	"os"
	"path/filepath"
	"testing"
)

func TestStatusDetectsLinkedWorkspace(t *testing.T) {
	root := t.TempDir()
	local := filepath.Join(root, "github", "oss")
	external := filepath.Join(root, "volume", "oss")
	writeWorkspaceManifest(t, filepath.Join(root, "configctl", "workspaces.toml"), local, external, false)
	if err := os.MkdirAll(external, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Dir(local), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(external, local); err != nil {
		t.Fatal(err)
	}

	status, err := Status(Options{ManifestPath: filepath.Join(root, "configctl", "workspaces.toml")})
	if err != nil {
		t.Fatal(err)
	}
	if status.Counts["linked"] != 1 {
		t.Fatalf("counts = %#v, want linked=1", status.Counts)
	}
}

func TestVerifyAllowsOptionalMissingExternalAsWarning(t *testing.T) {
	root := t.TempDir()
	local := filepath.Join(root, "github", "oss")
	external := filepath.Join(root, "volume", "oss")
	manifest := filepath.Join(root, "configctl", "workspaces.toml")
	writeWorkspaceManifest(t, manifest, local, external, false)

	status, failures, err := Verify(Options{ManifestPath: manifest, Name: "oss"})
	if err != nil {
		t.Fatal(err)
	}
	if len(failures) != 0 {
		t.Fatalf("optional missing external should not fail, got %#v", failures)
	}
	if len(status.Diagnostics) != 1 || status.Diagnostics[0].Severity != "warning" {
		t.Fatalf("expected warning diagnostic, got %#v", status.Diagnostics)
	}
}

func TestLinkRefusesRealDirectory(t *testing.T) {
	root := t.TempDir()
	local := filepath.Join(root, "github", "oss")
	external := filepath.Join(root, "volume", "oss")
	manifest := filepath.Join(root, "configctl", "workspaces.toml")
	writeWorkspaceManifest(t, manifest, local, external, false)
	if err := os.MkdirAll(local, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(external, 0o755); err != nil {
		t.Fatal(err)
	}

	_, err := Link(Options{ManifestPath: manifest, Name: "oss"})
	if err == nil {
		t.Fatal("expected real directory refusal")
	}
}

func TestLinkDryRunDoesNotMutate(t *testing.T) {
	root := t.TempDir()
	local := filepath.Join(root, "github", "oss")
	external := filepath.Join(root, "volume", "oss")
	manifest := filepath.Join(root, "configctl", "workspaces.toml")
	writeWorkspaceManifest(t, manifest, local, external, false)
	if err := os.MkdirAll(external, 0o755); err != nil {
		t.Fatal(err)
	}

	result, err := Link(Options{ManifestPath: manifest, Name: "oss", DryRun: true})
	if err != nil {
		t.Fatal(err)
	}
	if !result.Changed {
		t.Fatal("expected dry-run to report planned change")
	}
	if _, err := os.Lstat(local); !os.IsNotExist(err) {
		t.Fatalf("dry-run should not create local link, err=%v", err)
	}
}

func writeWorkspaceManifest(t *testing.T, path string, local string, external string, required bool) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	requiredValue := "false"
	if required {
		requiredValue = "true"
	}
	content := `schema_version = "configctl.workspaces.v1"

[[workspaces]]
name = "oss"
local = "` + local + `"
external = "` + external + `"
mode = "link"
required = ` + requiredValue + `
`
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}
