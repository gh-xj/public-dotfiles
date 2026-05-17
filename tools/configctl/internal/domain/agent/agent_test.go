package agent

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestSkillsStatusUsesPathLookupForBareCommand(t *testing.T) {
	root := t.TempDir()
	privateRepo := filepath.Join(root, "private-config")
	writeAgentFile(t, filepath.Join(privateRepo, "skills.profile.yaml"), "schema_version: test\n", 0o644)
	t.Setenv("PATH", filepath.Join(root, "empty-bin"))

	status := SkillsStatusResult(Options{
		PublicRepoDir:   filepath.Join(root, "public-dotfiles"),
		PrivateRepoDir:  privateRepo,
		HomeDir:         filepath.Join(root, "home"),
		SkillsetBin:     "definitely-not-skillset",
		SkillsetProfile: filepath.Join(privateRepo, "skills.profile.yaml"),
		SkillsetHome:    filepath.Join(root, "home"),
	})

	if status.SkillsetFound {
		t.Fatal("bare command missing from PATH should not be marked found")
	}
	if len(status.Diagnostics) != 1 || status.Diagnostics[0].Code != "agent.skills.skillset_missing" {
		t.Fatalf("diagnostics = %#v, want skillset_missing", status.Diagnostics)
	}
}

func TestSaveCodexAuthForcesSnapshotMode(t *testing.T) {
	root := t.TempDir()
	privateRepo := filepath.Join(root, "private-config")
	authPath := filepath.Join(privateRepo, ".codex", "auth.json")
	snapshotPath := filepath.Join(privateRepo, ".codex", "auth.api.json")
	writeAgentFile(t, authPath, `{"auth_mode":"chatgpt"}`, 0o600)
	writeAgentFile(t, snapshotPath, `{"auth_mode":"api-key"}`, 0o644)

	result, err := SaveCodexAuth(Options{
		PublicRepoDir:  filepath.Join(root, "public-dotfiles"),
		PrivateRepoDir: privateRepo,
		HomeDir:        filepath.Join(root, "home"),
	}, "api")
	if err != nil {
		t.Fatalf("SaveCodexAuth returned error: %v diagnostics=%#v", err, result.Diagnostics)
	}
	assertFileMode(t, snapshotPath, 0o600)
}

func TestUseCodexAuthForcesAuthAndBackupMode(t *testing.T) {
	root := t.TempDir()
	privateRepo := filepath.Join(root, "private-config")
	authPath := filepath.Join(privateRepo, ".codex", "auth.json")
	snapshotPath := filepath.Join(privateRepo, ".codex", "auth.api.json")
	writeAgentFile(t, authPath, `{"auth_mode":"chatgpt"}`, 0o644)
	writeAgentFile(t, snapshotPath, `{"auth_mode":"api-key"}`, 0o644)
	now := time.Date(2026, 5, 17, 1, 2, 3, 0, time.UTC)

	result, err := UseCodexAuth(Options{
		PublicRepoDir:  filepath.Join(root, "public-dotfiles"),
		PrivateRepoDir: privateRepo,
		HomeDir:        filepath.Join(root, "home"),
		Now:            now,
	}, "api")
	if err != nil {
		t.Fatalf("UseCodexAuth returned error: %v diagnostics=%#v", err, result.Diagnostics)
	}
	assertFileMode(t, authPath, 0o600)
	assertFileMode(t, authPath+".bak-20260517-010203", 0o600)
}

func writeAgentFile(t *testing.T, path string, content string, mode os.FileMode) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), mode); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, mode); err != nil {
		t.Fatal(err)
	}
}

func assertFileMode(t *testing.T, path string, want os.FileMode) {
	t.Helper()
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if got := info.Mode().Perm(); got != want {
		t.Fatalf("%s mode = %04o, want %04o", path, got, want)
	}
}
