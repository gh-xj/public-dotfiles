package report

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestResolveOperationReportPathDefaultsToInvokingRepoRunsDir(t *testing.T) {
	root := t.TempDir()
	now := time.Date(2026, 5, 17, 1, 2, 3, 0, time.UTC)

	path, err := ResolveOperationReportPath(ReportPathPolicy{
		RepoRoot: root,
		Command:  "home.apply",
		Now:      now,
	})
	if err != nil {
		t.Fatal(err)
	}

	want := filepath.Join(root, ".configctl", "runs", "20260517-010203-home-apply.json")
	if path != want {
		t.Fatalf("path = %q, want %q", path, want)
	}
}

func TestResolveOperationReportPathAcceptsExplicitFileOrDirectory(t *testing.T) {
	root := t.TempDir()
	now := time.Date(2026, 5, 17, 1, 2, 3, 0, time.UTC)
	explicitFile := filepath.Join(root, "report.json")
	explicitDir := filepath.Join(root, "reports")
	if err := os.MkdirAll(explicitDir, 0o755); err != nil {
		t.Fatal(err)
	}

	filePath, err := ResolveOperationReportPath(ReportPathPolicy{ExplicitPath: explicitFile, Command: "home.apply", Now: now})
	if err != nil {
		t.Fatal(err)
	}
	if filePath != explicitFile {
		t.Fatalf("explicit file path = %q, want %q", filePath, explicitFile)
	}

	dirPath, err := ResolveOperationReportPath(ReportPathPolicy{ExplicitPath: explicitDir, Command: "home.apply", Now: now})
	if err != nil {
		t.Fatal(err)
	}
	want := filepath.Join(explicitDir, "20260517-010203-home-apply.json")
	if dirPath != want {
		t.Fatalf("explicit dir path = %q, want %q", dirPath, want)
	}
}

func TestSanitizeArgsRedactsSensitiveFlagValues(t *testing.T) {
	args, metadata := SanitizeArgs([]string{
		"agent",
		"codex-auth",
		"use",
		"--api-key=sk-live",
		"--token",
		"secret-token",
		"--public-repo",
		"/tmp/public-dotfiles",
		"OPENAI_API_KEY=secret",
	})

	want := []string{
		"agent",
		"codex-auth",
		"use",
		"--api-key=[REDACTED]",
		"--token",
		"[REDACTED]",
		"--public-repo",
		"/tmp/public-dotfiles",
		"OPENAI_API_KEY=[REDACTED]",
	}
	if len(args) != len(want) {
		t.Fatalf("args len = %d, want %d", len(args), len(want))
	}
	for i := range want {
		if args[i] != want[i] {
			t.Fatalf("args[%d] = %q, want %q", i, args[i], want[i])
		}
	}
	if !metadata.Applied {
		t.Fatal("expected redaction metadata to mark applied")
	}
	if len(metadata.Rules) != 4 {
		t.Fatalf("redaction hits = %#v, want 4", metadata.Rules)
	}
}

func TestWriteOperationReportCreatesParentDirectories(t *testing.T) {
	path := filepath.Join(t.TempDir(), ".configctl", "runs", "report.json")
	operation := NewOperationReport(OperationReportInput{
		Command: "home.apply",
		OK:      true,
		Args:    []string{"home", "apply", "--token", "secret"},
	})

	if err := WriteOperationReport(path, operation); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) == "" {
		t.Fatal("expected report data")
	}
}
