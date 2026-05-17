package app

import (
	"io"

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
