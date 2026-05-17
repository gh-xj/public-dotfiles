package cmd

import (
	"errors"
	"fmt"
	"io"
	"os"

	"configctl/internal/logx"
	"configctl/internal/paths"
	"configctl/internal/report"
	"configctl/pkg/version"

	"github.com/alecthomas/kong"
)

type CLI struct {
	Verbose     bool             `short:"v" help:"enable debug logs"`
	NoColor     bool             `name:"no-color" help:"disable colored output"`
	JSON        bool             `name:"json" help:"emit machine-readable JSON output"`
	VersionFlag kong.VersionFlag `name:"version" help:"print version and exit"`

	Version VersionCmd `cmd:"" help:"print build metadata"`
	Home    HomeCmd    `cmd:"" help:"inspect repo-backed home topology"`
	App     AppCmd     `cmd:"" help:"inspect and apply app-specific config"`
}

type Runtime struct {
	CLI *CLI
	Out io.Writer
	Err io.Writer
}

type VersionCmd struct{}

func Execute(args []string) int {
	return execute(args, os.Stdout, os.Stderr)
}

func execute(args []string, stdout io.Writer, stderr io.Writer) int {
	var cli CLI
	exitRequested := false
	exitCode := 0
	parser, err := kong.New(&cli,
		kong.Name("configctl"),
		kong.Description("deterministic machine config control plane"),
		kong.Vars{"version": version.String()},
		kong.Exit(func(code int) {
			exitRequested = true
			exitCode = code
		}),
		kong.Writers(stdout, stderr),
	)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	ctx, err := parser.Parse(args)
	if exitRequested {
		return exitCode
	}
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 2
	}
	logx.Setup(logx.Options{Verbose: cli.Verbose, NoColor: cli.NoColor, Writer: stderr})
	runtime := &Runtime{CLI: &cli, Out: stdout, Err: stderr}
	if err := ctx.Run(runtime); err != nil {
		var exit report.ExitError
		if errors.As(err, &exit) {
			return exit.Code
		}
		fmt.Fprintln(stderr, err)
		return 1
	}
	return 0
}

func (c *VersionCmd) Run(rt *Runtime) error {
	return rt.Emit(report.New("version", true, false, false, "configctl "+version.String(), map[string]string{
		"name":    "configctl",
		"version": version.Version,
		"commit":  version.Commit,
		"date":    version.Date,
	}, nil))
}

func (rt *Runtime) Emit(env report.Envelope) error {
	return report.Write(rt.Out, env, rt.CLI.JSON)
}

func (rt *Runtime) Fail(command string, dryRun bool, summary string, data any, diagnostics []report.Diagnostic) error {
	if err := rt.Emit(report.New(command, false, false, dryRun, summary, data, diagnostics)); err != nil {
		return err
	}
	return report.ExitError{Code: 1}
}

func defaultLexiconPath(explicit string) (string, report.Diagnostic) {
	if explicit != "" {
		return paths.Expand(explicit), report.Diagnostic{}
	}
	resolved, err := paths.TypeWhisperLexiconPath()
	if err == nil {
		return resolved, report.Diagnostic{}
	}
	return resolved, report.Diagnostic{
		Severity: "warning",
		Code:     "configctl.repo_root_not_found",
		Message:  err.Error(),
	}
}

func defaultStoreDir(explicit string) string {
	if explicit != "" {
		return paths.Expand(explicit)
	}
	return paths.TypeWhisperStoreDir()
}
