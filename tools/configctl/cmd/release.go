package cmd

import (
	"context"
	"fmt"

	appctx "configctl/internal/app"
	releasedomain "configctl/internal/domain/release"
	"configctl/internal/report"
)

type ReleaseCmd struct {
	Capture ReleaseCaptureCmd `cmd:"" help:"capture explicit paths for a constrained release commit"`
}

type ReleaseCaptureCmd struct {
	Registry         string   `name:"registry" help:"repo registry path" type:"path"`
	Path             []string `name:"path" short:"p" help:"explicit path to include; repeat for multiple paths" type:"path"`
	OperationReports []string `name:"operation-report" short:"r" help:"release-eligible operation report to include; repeat for multiple reports" type:"path"`
	Message          string   `name:"message" short:"m" help:"commit message for --apply"`
	Apply            bool     `name:"apply" help:"stage and commit the captured paths"`
	Push             bool     `name:"push" help:"push committed repos after --apply"`
	ReportOut        string   `name:"report-out" help:"write release run report to this file or directory" type:"path"`
}

func (c *ReleaseCaptureCmd) Run(rt *appctx.Runtime) error {
	command := "release.capture"
	result, err := releasedomain.Capture(context.Background(), releasedomain.CaptureOptions{
		RegistryPath:     c.Registry,
		Paths:            c.Path,
		OperationReports: c.OperationReports,
		Message:          c.Message,
		Apply:            c.Apply,
		Push:             c.Push,
	})
	ok := err == nil
	if c.ReportOut != "" || c.Apply {
		result.OperationReportPath, result.Diagnostics = writeReleaseReport(rt, command, c.ReportOut, result, ok)
	}
	if hasRequiredFailures(result.Diagnostics) {
		return rt.Fail(command, result.DryRun, releaseSummary(result), result, result.Diagnostics)
	}
	return rt.Emit(report.New(command, ok, c.Apply, result.DryRun, releaseSummary(result), result, result.Diagnostics))
}

func writeReleaseReport(rt *appctx.Runtime, command string, reportOut string, result releasedomain.CaptureResult, ok bool) (string, []report.Diagnostic) {
	diagnostics := append([]report.Diagnostic{}, result.Diagnostics...)
	repoRoots := map[string]string{}
	for _, repoResult := range result.Repos {
		repoRoots[repoResult.Name] = repoResult.Root
	}
	var verificationHints []string
	for _, plan := range result.VerificationCommands {
		verificationHints = append(verificationHints, plan.Command+" "+joinArgs(plan.Args))
	}
	path, err := rt.WriteOperationReport(report.OperationReportInput{
		Command:           command,
		OK:                ok,
		Changed:           hasReleaseCommits(result),
		DryRun:            result.DryRun,
		ReleaseEligible:   false,
		RepoRoots:         repoRoots,
		TouchedPaths:      result.TouchedPaths,
		VerificationHints: verificationHints,
		Diagnostics:       result.Diagnostics,
		Metadata: map[string]any{
			"release": result,
		},
	}, reportOut)
	if err != nil {
		diagnostics = append(diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "operation_report.write_failed",
			Message:  err.Error(),
		})
		return "", diagnostics
	}
	return path, diagnostics
}

func releaseSummary(result releasedomain.CaptureResult) string {
	commits := 0
	for _, repoResult := range result.Repos {
		if repoResult.CommitHash != "" {
			commits++
		}
	}
	mode := "dry-run"
	if result.Apply {
		mode = "apply"
	}
	return fmt.Sprintf("release capture %s: %d repo(s), %d path(s), %d commit(s)", mode, len(result.Repos), len(result.TouchedPaths), commits)
}

func hasReleaseCommits(result releasedomain.CaptureResult) bool {
	for _, repoResult := range result.Repos {
		if repoResult.CommitHash != "" {
			return true
		}
	}
	return false
}

func joinArgs(args []string) string {
	out := ""
	for i, arg := range args {
		if i > 0 {
			out += " "
		}
		out += arg
	}
	return out
}
