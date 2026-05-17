package app

import (
	"io"
	"time"

	"configctl/internal/adapters/reporoot"
	"configctl/internal/report"
)

type Options struct {
	JSON    bool
	Verbose bool
	NoColor bool
	Args    []string
}

type Runtime struct {
	Options Options
	Out     io.Writer
	Err     io.Writer
}

func NewRuntime(opts Options, stdout io.Writer, stderr io.Writer) *Runtime {
	opts.Args = append([]string{}, opts.Args...)
	return &Runtime{
		Options: opts,
		Out:     stdout,
		Err:     stderr,
	}
}

func (rt *Runtime) Emit(env report.Envelope) error {
	return report.Write(rt.Out, env, rt.Options.JSON)
}

func (rt *Runtime) Fail(command string, dryRun bool, summary string, data any, diagnostics []report.Diagnostic) error {
	if err := rt.Emit(report.New(command, false, false, dryRun, summary, data, diagnostics)); err != nil {
		return err
	}
	return report.ExitError{Code: 1}
}

func (rt *Runtime) JSONOutput() bool {
	return rt.Options.JSON
}

func (rt *Runtime) SanitizedArgs() ([]string, report.RedactionMetadata) {
	return report.SanitizeArgs(rt.Options.Args)
}

func (rt *Runtime) WriteOperationReport(input report.OperationReportInput, explicitPath string) (string, error) {
	now := time.Now()
	if input.StartedAt.IsZero() {
		input.StartedAt = now
	}
	if input.FinishedAt.IsZero() {
		input.FinishedAt = now
	}
	input.Args = rt.Options.Args
	root, err := reporoot.GitFinder{}.Find("")
	if err != nil {
		if explicitPath == "" {
			return "", err
		}
		root.Path = ""
	}
	if input.RepoRoots == nil {
		input.RepoRoots = map[string]string{}
	}
	if root.Path != "" {
		if _, ok := input.RepoRoots["invoking"]; !ok {
			input.RepoRoots["invoking"] = root.Path
		}
	}
	repoRoot := root.Path
	if repoRoot == "" {
		repoRoot = "."
	}
	path, err := report.ResolveOperationReportPath(report.ReportPathPolicy{
		RepoRoot:     repoRoot,
		ExplicitPath: explicitPath,
		Command:      input.Command,
		Now:          now,
	})
	if err != nil {
		return "", err
	}
	return path, report.WriteOperationReport(path, report.NewOperationReport(input))
}
