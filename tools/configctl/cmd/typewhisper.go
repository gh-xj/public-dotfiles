package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"

	appctx "configctl/internal/app"
	"configctl/internal/domain/typewhisper"
	"configctl/internal/paths"
	"configctl/internal/report"
)

type AppCmd struct {
	TypeWhisper TypeWhisperCmd `cmd:"" name:"typewhisper" help:"manage TypeWhisper vocabulary stores"`
	Nvim        NvimCmd        `cmd:"" name:"nvim" help:"verify Neovim config"`
	Lazygit     LazygitCmd     `cmd:"" name:"lazygit" help:"verify Lazygit config"`
	Ghostty     GhosttyCmd     `cmd:"" name:"ghostty" help:"verify Ghostty config"`
	Tmux        TmuxCmd        `cmd:"" name:"tmux" help:"verify tmux config"`
	Karabiner   KarabinerCmd   `cmd:"" name:"karabiner" help:"verify Karabiner config"`
	Terminal    TerminalCmd    `cmd:"" name:"terminal" help:"verify terminal workflow"`
}

type TypeWhisperCmd struct {
	Validate TypeWhisperValidateCmd `cmd:"" help:"validate the repo TypeWhisper lexicon"`
	Status   TypeWhisperStatusCmd   `cmd:"" help:"summarize live TypeWhisper stores"`
	Import   TypeWhisperImportCmd   `cmd:"" help:"upsert the repo lexicon into live stores"`
	Export   TypeWhisperExportCmd   `cmd:"" help:"export live stores as lexicon JSON"`
}

type TypeWhisperValidateCmd struct {
	Lexicon string `help:"repo lexicon path" type:"path"`
}

type TypeWhisperStatusCmd struct {
	StoreDir string `name:"store-dir" help:"live TypeWhisper store directory" type:"path"`
}

type TypeWhisperImportCmd struct {
	Lexicon      string `help:"repo lexicon path" type:"path"`
	StoreDir     string `name:"store-dir" help:"live TypeWhisper store directory" type:"path"`
	DryRun       bool   `name:"dry-run" help:"preview changes without writing stores"`
	AllowRunning bool   `name:"allow-running" help:"allow import while TypeWhisper is running"`
	ReportOut    string `name:"report-out" help:"write operation report to this file or directory" type:"path"`
}

type TypeWhisperExportCmd struct {
	StoreDir string `name:"store-dir" help:"live TypeWhisper store directory" type:"path"`
	Output   string `name:"output" help:"write exported lexicon to this path" type:"path"`
}

func (c *TypeWhisperValidateCmd) Run(rt *appctx.Runtime) error {
	command := "app.typewhisper.validate"
	lexiconPath, warning := defaultLexiconPath(c.Lexicon)
	lexicon, diagnostics, err := typewhisper.LoadLexicon(lexiconPath)
	diagnostics = appendWarning(diagnostics, warning)
	data := map[string]any{
		"lexicon_path": lexiconPath,
		"lexicon":      lexicon.Summary(),
	}
	if err != nil {
		return rt.Fail(command, false, "invalid TypeWhisper lexicon", data, diagnostics)
	}
	return rt.Emit(report.New(command, true, false, false, "TypeWhisper lexicon valid: "+typewhisper.SummaryText(lexicon.Summary()), data, diagnostics))
}

func (c *TypeWhisperStatusCmd) Run(rt *appctx.Runtime) error {
	command := "app.typewhisper.status"
	ctx := context.Background()
	storeDir := defaultStoreDir(c.StoreDir)
	running := typewhisper.IsRunning(ctx)
	status, diagnostics, err := typewhisper.Status(ctx, storeDir, running)
	data := map[string]any{"status": status}
	if err != nil {
		return rt.Fail(command, false, "could not inspect TypeWhisper stores", data, diagnostics)
	}
	summary := fmt.Sprintf("TypeWhisper: %d terms, %d corrections, %d snippets", status.Terms, status.Corrections, status.Snippets)
	return rt.Emit(report.New(command, true, false, false, summary, data, diagnostics))
}

func (c *TypeWhisperImportCmd) Run(rt *appctx.Runtime) error {
	command := "app.typewhisper.import"
	ctx := context.Background()
	lexiconPath, warning := defaultLexiconPath(c.Lexicon)
	storeDir := defaultStoreDir(c.StoreDir)
	lexicon, diagnostics, err := typewhisper.LoadLexicon(lexiconPath)
	diagnostics = appendWarning(diagnostics, warning)
	if err != nil {
		reportPath, reportDiagnostics := c.maybeWriteReport(rt, command, false, false, lexiconPath, storeDir, nil, diagnostics)
		diagnostics = reportDiagnostics
		return rt.Fail(command, c.DryRun, "invalid TypeWhisper lexicon", map[string]any{
			"lexicon_path":          lexiconPath,
			"store_dir":             storeDir,
			"operation_report_path": reportPath,
		}, diagnostics)
	}
	running := typewhisper.IsRunning(ctx)
	if running && !c.DryRun && !c.AllowRunning {
		reportPath, reportDiagnostics := c.maybeWriteReport(rt, command, false, false, lexiconPath, storeDir, nil, append(diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "typewhisper.app_running",
			Message:  "TypeWhisper is running",
		}))
		return rt.Fail(command, c.DryRun, "TypeWhisper is running; quit it before import or pass --allow-running", map[string]any{
			"lexicon_path":          lexiconPath,
			"store_dir":             storeDir,
			"typewhisper_running":   true,
			"allow_running":         c.AllowRunning,
			"lexicon":               lexicon.Summary(),
			"dictionary_store_path": filepath.Join(storeDir, "dictionary.store"),
			"snippets_store_path":   filepath.Join(storeDir, "snippets.store"),
			"operation_report_path": reportPath,
		}, reportDiagnostics)
	}
	plan, planDiagnostics, err := typewhisper.PlanImport(ctx, lexicon, storeDir, running)
	diagnostics = append(diagnostics, planDiagnostics...)
	if err != nil {
		reportPath, reportDiagnostics := c.maybeWriteReport(rt, command, false, false, lexiconPath, storeDir, nil, diagnostics)
		diagnostics = reportDiagnostics
		return rt.Fail(command, c.DryRun, "could not plan TypeWhisper import", map[string]any{
			"lexicon_path":          lexiconPath,
			"store_dir":             storeDir,
			"lexicon":               lexicon.Summary(),
			"operation_report_path": reportPath,
		}, diagnostics)
	}
	if c.DryRun {
		summary := fmt.Sprintf("dry-run TypeWhisper import: dictionary updates=%d insertions=%d, snippet updates=%d insertions=%d", plan.Dictionary.Updates, plan.Dictionary.Insertions, plan.Snippets.Updates, plan.Snippets.Insertions)
		reportPath, reportDiagnostics := c.maybeWriteReport(rt, command, true, false, lexiconPath, storeDir, nil, diagnostics)
		if hasErrorDiagnostics(reportDiagnostics, "operation_report") {
			return rt.Fail(command, c.DryRun, "could not write TypeWhisper import operation report", map[string]any{
				"lexicon_path":          lexiconPath,
				"store_dir":             storeDir,
				"plan":                  plan,
				"operation_report_path": reportPath,
			}, reportDiagnostics)
		}
		return rt.Emit(report.New(command, true, false, true, summary, map[string]any{
			"lexicon_path":          lexiconPath,
			"store_dir":             storeDir,
			"plan":                  plan,
			"operation_report_path": reportPath,
		}, reportDiagnostics))
	}
	repoRoot, _ := paths.PrivateConfigRoot()
	result, applyDiagnostics, err := typewhisper.ApplyImport(ctx, lexicon, storeDir, repoRoot, time.Now(), running)
	diagnostics = append(diagnostics, applyDiagnostics...)
	if err != nil {
		reportPath, reportDiagnostics := c.maybeWriteReport(rt, command, false, false, lexiconPath, storeDir, nil, diagnostics)
		diagnostics = reportDiagnostics
		return rt.Fail(command, false, "could not import TypeWhisper lexicon", map[string]any{
			"lexicon_path":          lexiconPath,
			"store_dir":             storeDir,
			"plan":                  plan,
			"operation_report_path": reportPath,
		}, diagnostics)
	}
	summary := fmt.Sprintf("imported TypeWhisper lexicon: dictionary updates=%d insertions=%d, snippet updates=%d insertions=%d", result.Plan.Dictionary.Updates, result.Plan.Dictionary.Insertions, result.Plan.Snippets.Updates, result.Plan.Snippets.Insertions)
	reportPath, reportDiagnostics := c.maybeWriteReport(rt, command, true, typewhisper.PlanChanged(result.Plan), lexiconPath, storeDir, &result, diagnostics)
	if hasErrorDiagnostics(reportDiagnostics, "operation_report") {
		return rt.Fail(command, false, "could not write TypeWhisper import operation report", map[string]any{
			"lexicon_path":          lexiconPath,
			"store_dir":             storeDir,
			"result":                result,
			"operation_report_path": reportPath,
		}, reportDiagnostics)
	}
	return rt.Emit(report.New(command, true, typewhisper.PlanChanged(result.Plan), false, summary, map[string]any{
		"lexicon_path":          lexiconPath,
		"store_dir":             storeDir,
		"result":                result,
		"operation_report_path": reportPath,
	}, reportDiagnostics))
}

func (c *TypeWhisperImportCmd) maybeWriteReport(rt *appctx.Runtime, command string, ok bool, changed bool, lexiconPath string, storeDir string, result *typewhisper.ImportResult, diagnostics []report.Diagnostic) (string, []report.Diagnostic) {
	outDiagnostics := append([]report.Diagnostic{}, diagnostics...)
	if c.DryRun && c.ReportOut == "" {
		return "", outDiagnostics
	}
	touched := []string{filepath.Join(storeDir, "dictionary.store"), filepath.Join(storeDir, "snippets.store")}
	var backups []string
	if result != nil && result.BackupDir != "" {
		backups = append(backups, result.BackupDir)
	}
	repoRoots := map[string]string{}
	if repoRoot, err := paths.PrivateConfigRoot(); err == nil {
		repoRoots["private"] = repoRoot
	}
	path, err := rt.WriteOperationReport(report.OperationReportInput{
		Command:           command,
		OK:                ok,
		Changed:           changed,
		DryRun:            c.DryRun,
		ReleaseEligible:   false,
		RepoRoots:         repoRoots,
		TouchedPaths:      touched,
		Backups:           backups,
		VerificationHints: []string{"configctl app typewhisper status"},
		Diagnostics:       diagnostics,
	}, c.ReportOut)
	if err != nil {
		outDiagnostics = append(outDiagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "operation_report.write_failed",
			Message:  err.Error(),
		})
		return "", outDiagnostics
	}
	return path, outDiagnostics
}

func (c *TypeWhisperExportCmd) Run(rt *appctx.Runtime) error {
	command := "app.typewhisper.export"
	ctx := context.Background()
	storeDir := defaultStoreDir(c.StoreDir)
	lexicon, diagnostics, err := typewhisper.Export(ctx, storeDir)
	if err != nil {
		return rt.Fail(command, false, "could not export TypeWhisper stores", map[string]any{
			"store_dir": storeDir,
		}, diagnostics)
	}
	output := paths.Expand(c.Output)
	if output != "" {
		if err := writeLexicon(output, lexicon); err != nil {
			return rt.Fail(command, false, "could not write exported TypeWhisper lexicon", map[string]any{
				"store_dir":    storeDir,
				"output_path":  output,
				"lexicon":      lexicon.Summary(),
				"write_target": output,
			}, []report.Diagnostic{{
				Severity: "error",
				Code:     "typewhisper.export_write_failed",
				Message:  err.Error(),
				Path:     output,
			}})
		}
		return rt.Emit(report.New(command, true, false, false, "exported TypeWhisper lexicon to "+output, map[string]any{
			"store_dir":   storeDir,
			"output_path": output,
			"lexicon":     lexicon.Summary(),
		}, diagnostics))
	}
	if rt.JSONOutput() {
		return rt.Emit(report.New(command, true, false, false, "exported TypeWhisper lexicon", map[string]any{
			"store_dir": storeDir,
			"lexicon":   lexicon,
		}, diagnostics))
	}
	encoder := json.NewEncoder(rt.Out)
	encoder.SetIndent("", "  ")
	return encoder.Encode(lexicon)
}

func writeLexicon(path string, lexicon typewhisper.Lexicon) error {
	dir := filepath.Dir(path)
	if dir != "." && dir != "" {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}
	data, err := json.MarshalIndent(lexicon, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	return os.WriteFile(path, data, 0o644)
}

func appendWarning(diagnostics []report.Diagnostic, warning report.Diagnostic) []report.Diagnostic {
	if warning.Code == "" {
		return diagnostics
	}
	return append(diagnostics, warning)
}
