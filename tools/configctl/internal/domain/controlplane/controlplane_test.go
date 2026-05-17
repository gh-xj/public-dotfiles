package controlplane

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

func TestAgentCheckSkipsOptionalMissingPrivateRepo(t *testing.T) {
	root := t.TempDir()
	registryPath := filepath.Join(root, "public-dotfiles", "configctl", "repos.toml")
	writeControlplaneFile(t, registryPath, `schema_version = "configctl.repos.v1"

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

	result := agentCheck(Options{RegistryPath: registryPath}).Run(context.Background())

	if !result.OK {
		t.Fatalf("optional missing private repo should skip successfully: %#v", result)
	}
	if len(result.Diagnostics) != 1 || result.Diagnostics[0].Code != "agent.private_repo_missing" {
		t.Fatalf("diagnostics = %#v, want agent.private_repo_missing", result.Diagnostics)
	}
}

func writeControlplaneFile(t *testing.T, path string, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}
