package cmd

import (
	"fmt"

	appctx "configctl/internal/app"
	"configctl/internal/domain/workspace"
	"configctl/internal/report"
)

type WorkspaceCmd struct {
	Status WorkspaceStatusCmd `cmd:"" help:"summarize workspace links"`
	Verify WorkspaceVerifyCmd `cmd:"" help:"verify workspace links"`
	Link   WorkspaceLinkCmd   `cmd:"" help:"link a workspace to its external path"`
}

type workspaceOptions struct {
	Manifest string `name:"manifest" help:"workspace manifest path" type:"path"`
}

type WorkspaceStatusCmd struct {
	workspaceOptions
}

type WorkspaceVerifyCmd struct {
	workspaceOptions
	Name string `arg:"" optional:"" help:"workspace name to verify"`
}

type WorkspaceLinkCmd struct {
	workspaceOptions
	Name      string `arg:"" help:"workspace name to link"`
	DryRun    bool   `name:"dry-run" help:"preview link action without changing the filesystem"`
	ReportOut string `name:"report-out" help:"write operation report to this file or directory" type:"path"`
}

func (c *WorkspaceStatusCmd) Run(rt *appctx.Runtime) error {
	command := "workspace.status"
	status, err := workspace.Status(workspace.Options{ManifestPath: c.Manifest})
	if err != nil {
		return rt.Fail(command, false, "could not inspect workspace links", status, status.Diagnostics)
	}
	return rt.Emit(report.New(command, true, false, false, workspaceStatusSummary(status), status, status.Diagnostics))
}

func (c *WorkspaceVerifyCmd) Run(rt *appctx.Runtime) error {
	command := "workspace.verify"
	status, failures, err := workspace.Verify(workspace.Options{ManifestPath: c.Manifest, Name: c.Name})
	if err != nil {
		return rt.Fail(command, false, "could not verify workspace links", status, status.Diagnostics)
	}
	diagnostics := append([]report.Diagnostic{}, status.Diagnostics...)
	diagnostics = append(diagnostics, failures...)
	if hasRequiredFailures(failures) {
		return rt.Fail(command, false, fmt.Sprintf("workspace verification failed: %d issue(s)", len(failures)), status, diagnostics)
	}
	return rt.Emit(report.New(command, true, false, false, workspaceVerifySummary(status), status, diagnostics))
}

func (c *WorkspaceLinkCmd) Run(rt *appctx.Runtime) error {
	command := "workspace.link"
	result, err := workspace.Link(workspace.Options{ManifestPath: c.Manifest, Name: c.Name, DryRun: c.DryRun})
	result.OperationReportPath, result.Diagnostics = c.maybeWriteReport(rt, command, result, err == nil)
	if err != nil {
		return rt.Fail(command, c.DryRun, "could not link workspace", result, result.Diagnostics)
	}
	if hasErrorDiagnostics(result.Diagnostics, "operation_report") {
		return rt.Fail(command, c.DryRun, "could not write workspace link operation report", result, result.Diagnostics)
	}
	return rt.Emit(report.New(command, true, result.Changed, c.DryRun, workspaceLinkSummary(result), result, result.Diagnostics))
}

func (c *WorkspaceLinkCmd) maybeWriteReport(rt *appctx.Runtime, command string, result workspace.LinkResult, ok bool) (string, []report.Diagnostic) {
	diagnostics := append([]report.Diagnostic{}, result.Diagnostics...)
	if c.DryRun && c.ReportOut == "" {
		return "", diagnostics
	}
	var touched []string
	if result.State.Local != "" {
		touched = append(touched, result.State.Local)
	}
	path, err := rt.WriteOperationReport(report.OperationReportInput{
		Command:           command,
		OK:                ok,
		Changed:           result.Changed,
		DryRun:            c.DryRun,
		ReleaseEligible:   false,
		TouchedPaths:      touched,
		VerificationHints: []string{"configctl workspace verify " + c.Name},
		Diagnostics:       result.Diagnostics,
	}, c.ReportOut)
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

func workspaceStatusSummary(status workspace.StatusResult) string {
	return fmt.Sprintf("workspace status: %d workspaces, linked=%d, missing=%d, external_missing=%d",
		len(status.Workspaces),
		status.Counts["linked"],
		status.Counts["missing"],
		status.Counts["external_missing"],
	)
}

func workspaceVerifySummary(status workspace.StatusResult) string {
	return fmt.Sprintf("workspace links verified: %d workspace(s)", len(status.Workspaces))
}

func workspaceLinkSummary(result workspace.LinkResult) string {
	if result.Changed {
		if result.DryRun {
			return "workspace link dry-run: " + result.State.Name
		}
		return "workspace linked: " + result.State.Name
	}
	return "workspace link skipped: " + result.State.Name
}

func hasRequiredFailures(diagnostics []report.Diagnostic) bool {
	for _, diagnostic := range diagnostics {
		if diagnostic.Severity == "error" {
			return true
		}
	}
	return false
}
