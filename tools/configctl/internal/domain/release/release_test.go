package release

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"configctl/internal/adapters/process"
	"configctl/internal/report"
)

func TestCaptureDryRunScopesPathsToManagedRepos(t *testing.T) {
	publicRoot := t.TempDir()
	privateRoot := t.TempDir()
	publicPath := filepath.Join(publicRoot, "docs", "plan.md")
	privatePath := filepath.Join(privateRoot, "Brewfile")
	writeReleaseFile(t, publicPath, "# plan\n")
	writeReleaseFile(t, privatePath, "brew \"gh\"\n")

	result, err := Capture(context.Background(), CaptureOptions{
		Paths: []string{publicPath, privatePath},
		RepoRoots: map[string]string{
			"public-dotfiles": publicRoot,
			"private-config":  privateRoot,
		},
		Runner: fakeRunner{},
	})
	if err != nil {
		t.Fatal(err)
	}
	if !result.DryRun {
		t.Fatal("expected dry-run by default")
	}
	if got := len(result.Repos); got != 2 {
		t.Fatalf("repos = %d, want 2", got)
	}
	if got := len(result.TouchedPaths); got != 2 {
		t.Fatalf("touched paths = %d, want 2", got)
	}
}

func TestCaptureRejectsPathOutsideManagedRepos(t *testing.T) {
	_, err := Capture(context.Background(), CaptureOptions{
		Paths: []string{filepath.Join(t.TempDir(), "outside.txt")},
		RepoRoots: map[string]string{
			"public-dotfiles": t.TempDir(),
		},
		Runner: fakeRunner{},
	})
	if err == nil {
		t.Fatal("expected outside path to fail")
	}
}

func TestCaptureRejectsIncompatibleOperationReportSchema(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "file.txt")
	writeReleaseFile(t, path, "changed\n")
	reportPath := filepath.Join(t.TempDir(), "operation.json")
	operation := report.NewOperationReport(report.OperationReportInput{
		Command:         "test",
		OK:              true,
		Changed:         true,
		ReleaseEligible: true,
		TouchedPaths:    []string{path},
	})
	operation.SchemaVersion = "configctl.operation.v2"
	if err := report.WriteOperationReport(reportPath, operation); err != nil {
		t.Fatal(err)
	}

	_, err := Capture(context.Background(), CaptureOptions{
		OperationReports: []string{reportPath},
		RepoRoots: map[string]string{
			"public-dotfiles": root,
		},
		Runner: fakeRunner{},
	})
	if err == nil {
		t.Fatal("expected incompatible schema to fail")
	}
}

func TestCaptureAcceptsSameMajorOperationReportSchema(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "file.txt")
	writeReleaseFile(t, path, "changed\n")
	reportPath := filepath.Join(t.TempDir(), "operation.json")
	operation := report.NewOperationReport(report.OperationReportInput{
		Command:         "test",
		OK:              true,
		Changed:         true,
		ReleaseEligible: true,
		TouchedPaths:    []string{path},
	})
	operation.SchemaVersion = "configctl.operation.v1.1"
	if err := report.WriteOperationReport(reportPath, operation); err != nil {
		t.Fatal(err)
	}

	result, err := Capture(context.Background(), CaptureOptions{
		OperationReports: []string{reportPath},
		RepoRoots: map[string]string{
			"public-dotfiles": root,
		},
		Runner: fakeRunner{},
	})
	if err != nil {
		t.Fatal(err)
	}
	if got := len(result.TouchedPaths); got != 1 {
		t.Fatalf("touched paths = %d, want 1", got)
	}
}

type fakeRunner struct{}

func (fakeRunner) Run(context.Context, process.Invocation) (process.Result, error) {
	return process.Result{ExitCode: 0}, nil
}

func writeReleaseFile(t *testing.T, path string, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}
