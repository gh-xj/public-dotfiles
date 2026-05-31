package agent

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestPolicyStatusAcceptsSplitLiveAgentDirs(t *testing.T) {
	root := t.TempDir()
	homeDir := filepath.Join(root, "home")
	privateRepo := filepath.Join(root, "private-config")
	publicRepo := filepath.Join(root, "public-dotfiles")

	for _, path := range []string{
		filepath.Join(publicRepo, ".claude", "CLAUDE.md"),
		filepath.Join(publicRepo, ".claude", "settings.json"),
		filepath.Join(publicRepo, ".claude", "statusline-command.sh"),
		filepath.Join(publicRepo, ".codex", "rules", "default.rules"),
		filepath.Join(privateRepo, ".codex", "config.toml"),
		filepath.Join(privateRepo, ".codex", "hooks.json"),
	} {
		writeAgentFile(t, path, "test\n", 0o644)
	}
	mustSymlink(t, filepath.Join(publicRepo, ".claude", "CLAUDE.md"), filepath.Join(privateRepo, ".claude", "CLAUDE.md"))
	mustSymlink(t, filepath.Join(publicRepo, ".claude", "settings.json"), filepath.Join(privateRepo, ".claude", "settings.json"))
	mustSymlink(t, filepath.Join(publicRepo, ".claude", "statusline-command.sh"), filepath.Join(privateRepo, ".claude", "statusline-command.sh"))
	mustSymlink(t, filepath.Join(privateRepo, ".claude", "CLAUDE.md"), filepath.Join(privateRepo, ".codex", "AGENTS.md"))
	mustSymlink(t, filepath.Join(publicRepo, ".codex", "rules"), filepath.Join(privateRepo, ".codex", "rules"))

	for _, dir := range []string{filepath.Join(homeDir, ".claude"), filepath.Join(homeDir, ".codex")} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	for _, child := range []string{"CLAUDE.md", "settings.json", "statusline-command.sh"} {
		mustSymlink(t, filepath.Join(privateRepo, ".claude", child), filepath.Join(homeDir, ".claude", child))
	}
	for _, child := range []string{"AGENTS.md", "config.toml", "hooks.json", "rules"} {
		mustSymlink(t, filepath.Join(privateRepo, ".codex", child), filepath.Join(homeDir, ".codex", child))
	}

	status, err := PolicyStatusResult(Options{
		PublicRepoDir:  publicRepo,
		PrivateRepoDir: privateRepo,
		HomeDir:        homeDir,
	})
	if err != nil {
		t.Fatalf("PolicyStatusResult returned error: %v", err)
	}
	for _, diagnostic := range status.Diagnostics {
		if diagnostic.Severity == "error" {
			t.Fatalf("unexpected error diagnostic: %#v", diagnostic)
		}
	}
}

func TestPolicyStatusAcceptsHomeManagerStoreAgentLinks(t *testing.T) {
	root := t.TempDir()
	homeDir := filepath.Join(root, "home")
	privateRepo := filepath.Join(root, "private-config")
	publicRepo := filepath.Join(root, "public-dotfiles")
	storeDir := filepath.Join(root, "nix-store")

	for _, file := range []struct {
		path    string
		content string
	}{
		{filepath.Join(publicRepo, ".claude", "CLAUDE.md"), "claude policy\n"},
		{filepath.Join(publicRepo, ".claude", "settings.json"), "{}\n"},
		{filepath.Join(publicRepo, ".claude", "statusline-command.sh"), "#!/bin/sh\n"},
		{filepath.Join(publicRepo, ".codex", "rules", "default.rules"), "rule\n"},
		{filepath.Join(privateRepo, ".codex", "config.toml"), "model = \"test\"\n"},
		{filepath.Join(privateRepo, ".codex", "hooks.json"), "{}\n"},
	} {
		writeAgentFile(t, file.path, file.content, 0o644)
	}
	mustSymlink(t, filepath.Join(publicRepo, ".claude", "CLAUDE.md"), filepath.Join(privateRepo, ".claude", "CLAUDE.md"))
	mustSymlink(t, filepath.Join(publicRepo, ".claude", "settings.json"), filepath.Join(privateRepo, ".claude", "settings.json"))
	mustSymlink(t, filepath.Join(publicRepo, ".claude", "statusline-command.sh"), filepath.Join(privateRepo, ".claude", "statusline-command.sh"))
	mustSymlink(t, filepath.Join(privateRepo, ".claude", "CLAUDE.md"), filepath.Join(privateRepo, ".codex", "AGENTS.md"))
	mustSymlink(t, filepath.Join(publicRepo, ".codex", "rules"), filepath.Join(privateRepo, ".codex", "rules"))

	for _, dir := range []string{filepath.Join(homeDir, ".claude"), filepath.Join(homeDir, ".codex")} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	for _, child := range []string{"CLAUDE.md", "settings.json", "statusline-command.sh"} {
		storePath := filepath.Join(storeDir, "hm-claude-"+child)
		copyAgentFile(t, filepath.Join(privateRepo, ".claude", child), storePath)
		mustSymlink(t, storePath, filepath.Join(homeDir, ".claude", child))
	}
	for _, child := range []string{"AGENTS.md", "hooks.json", "rules"} {
		storePath := filepath.Join(storeDir, "hm-codex-"+child)
		copyAgentPath(t, filepath.Join(privateRepo, ".codex", child), storePath)
		mustSymlink(t, storePath, filepath.Join(homeDir, ".codex", child))
	}
	mustSymlink(t, filepath.Join(privateRepo, ".codex", "config.toml"), filepath.Join(homeDir, ".codex", "config.toml"))

	status, err := PolicyStatusResult(Options{
		PublicRepoDir:  publicRepo,
		PrivateRepoDir: privateRepo,
		HomeDir:        homeDir,
	})
	if err != nil {
		t.Fatalf("PolicyStatusResult returned error: %v", err)
	}
	for _, diagnostic := range status.Diagnostics {
		if diagnostic.Severity == "error" {
			t.Fatalf("unexpected error diagnostic: %#v", diagnostic)
		}
	}
}

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

func mustSymlink(t *testing.T, oldname string, newname string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(newname), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(oldname, newname); err != nil {
		t.Fatal(err)
	}
}

func copyAgentPath(t *testing.T, source string, destination string) {
	t.Helper()
	info, err := os.Stat(source)
	if err != nil {
		t.Fatal(err)
	}
	if info.IsDir() {
		entries, err := os.ReadDir(source)
		if err != nil {
			t.Fatal(err)
		}
		if err := os.MkdirAll(destination, 0o755); err != nil {
			t.Fatal(err)
		}
		for _, entry := range entries {
			copyAgentPath(t, filepath.Join(source, entry.Name()), filepath.Join(destination, entry.Name()))
		}
		return
	}
	copyAgentFile(t, source, destination)
}

func copyAgentFile(t *testing.T, source string, destination string) {
	t.Helper()
	data, err := os.ReadFile(source)
	if err != nil {
		t.Fatal(err)
	}
	writeAgentFile(t, destination, string(data), 0o644)
}
