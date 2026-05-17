package cmd

import (
	"context"
	"fmt"

	appctx "configctl/internal/app"
	"configctl/internal/domain/agent"
	"configctl/internal/report"
)

type AgentCmd struct {
	Status    AgentStatusCmd    `cmd:"" help:"summarize agent config topology"`
	Verify    AgentVerifyCmd    `cmd:"" help:"verify agent config topology"`
	Policy    AgentPolicyCmd    `cmd:"" help:"inspect shared agent policy links"`
	Skills    AgentSkillsCmd    `cmd:"" help:"wrap skillset desired-state checks"`
	CodexAuth AgentCodexAuthCmd `cmd:"" name:"codex-auth" help:"manage Codex auth snapshots"`
}

type agentOptions struct {
	PublicRepo      string `name:"public-repo" help:"public-dotfiles repo path" type:"path"`
	PrivateRepo     string `name:"private-repo" help:"private-config repo path" type:"path"`
	HomeDir         string `name:"home" help:"home directory to inspect" type:"path"`
	SkillsetBin     string `name:"skillset-bin" help:"skillset binary path"`
	SkillsetProfile string `name:"skillset-profile" help:"skills.profile.yaml path" type:"path"`
}

type AgentStatusCmd struct {
	agentOptions
}

type AgentVerifyCmd struct {
	agentOptions
}

type AgentPolicyCmd struct {
	Status AgentPolicyStatusCmd `cmd:"" help:"summarize shared policy links"`
	Verify AgentPolicyVerifyCmd `cmd:"" help:"verify shared policy links"`
}

type AgentPolicyStatusCmd struct {
	agentOptions
}

type AgentPolicyVerifyCmd struct {
	agentOptions
}

type AgentSkillsCmd struct {
	List   AgentSkillsListCmd   `cmd:"" help:"list skillset-managed entries"`
	Verify AgentSkillsVerifyCmd `cmd:"" help:"run skillset check"`
	Sync   AgentSkillsSyncCmd   `cmd:"" help:"run skillset apply"`
}

type AgentSkillsListCmd struct {
	agentOptions
}

type AgentSkillsVerifyCmd struct {
	agentOptions
}

type AgentSkillsSyncCmd struct {
	agentOptions
	DryRun    bool   `name:"dry-run" help:"preview skillset apply without writing"`
	ReportOut string `name:"report-out" help:"write operation report to this file or directory" type:"path"`
}

type AgentCodexAuthCmd struct {
	Status AgentCodexAuthStatusCmd `cmd:"" help:"summarize Codex auth state"`
	Save   AgentCodexAuthSaveCmd   `cmd:"" help:"save current Codex auth as a snapshot"`
	Use    AgentCodexAuthUseCmd    `cmd:"" help:"switch Codex auth to a snapshot"`
}

type AgentCodexAuthStatusCmd struct {
	agentOptions
}

type AgentCodexAuthSaveCmd struct {
	agentOptions
	Mode      string `arg:"" enum:"api,chatgpt" help:"snapshot name"`
	ReportOut string `name:"report-out" help:"write operation report to this file or directory" type:"path"`
}

type AgentCodexAuthUseCmd struct {
	agentOptions
	Mode      string `arg:"" enum:"api,chatgpt" help:"snapshot name"`
	ReportOut string `name:"report-out" help:"write operation report to this file or directory" type:"path"`
}

func (c *AgentStatusCmd) Run(rt *appctx.Runtime) error {
	command := "agent.status"
	status, err := agent.Status(c.options())
	if err != nil {
		return rt.Fail(command, false, "could not inspect agent topology", status, status.Diagnostics)
	}
	return rt.Emit(report.New(command, true, false, false, agent.Summary(status), status, status.Diagnostics))
}

func (c *AgentVerifyCmd) Run(rt *appctx.Runtime) error {
	command := "agent.verify"
	status, failures, err := agent.Verify(c.options())
	if err != nil {
		return rt.Fail(command, false, "could not verify agent topology", status, status.Diagnostics)
	}
	if len(failures) > 0 {
		return rt.Fail(command, false, fmt.Sprintf("agent verification failed: %d issue(s)", len(failures)), status, status.Diagnostics)
	}
	return rt.Emit(report.New(command, true, false, false, "agent topology verified", status, status.Diagnostics))
}

func (c *AgentPolicyStatusCmd) Run(rt *appctx.Runtime) error {
	command := "agent.policy.status"
	status, err := agent.PolicyStatusResult(c.options())
	if err != nil {
		return rt.Fail(command, false, "could not inspect agent policy links", status, status.Diagnostics)
	}
	return rt.Emit(report.New(command, true, false, false, fmt.Sprintf("agent policy: %d links", len(status.Links)), status, status.Diagnostics))
}

func (c *AgentPolicyVerifyCmd) Run(rt *appctx.Runtime) error {
	command := "agent.policy.verify"
	status, err := agent.PolicyStatusResult(c.options())
	if err != nil {
		return rt.Fail(command, false, "could not verify agent policy links", status, status.Diagnostics)
	}
	if hasRequiredFailures(status.Diagnostics) {
		return rt.Fail(command, false, fmt.Sprintf("agent policy verification failed: %d issue(s)", len(status.Diagnostics)), status, status.Diagnostics)
	}
	return rt.Emit(report.New(command, true, false, false, fmt.Sprintf("agent policy verified: %d links", len(status.Links)), status, status.Diagnostics))
}

func (c *AgentSkillsListCmd) Run(rt *appctx.Runtime) error {
	return emitSkillset(rt, "agent.skills.list", agent.Skillset(context.Background(), c.options(), "list", false))
}

func (c *AgentSkillsVerifyCmd) Run(rt *appctx.Runtime) error {
	return emitSkillset(rt, "agent.skills.verify", agent.Skillset(context.Background(), c.options(), "verify", false))
}

func (c *AgentSkillsSyncCmd) Run(rt *appctx.Runtime) error {
	command := "agent.skills.sync"
	result := agent.Skillset(context.Background(), c.options(), "sync", c.DryRun)
	if !c.DryRun || c.ReportOut != "" {
		result.OperationReportPath, result.Diagnostics = c.writeReport(rt, command, result)
	}
	return emitSkillset(rt, command, result)
}

func (c *AgentCodexAuthStatusCmd) Run(rt *appctx.Runtime) error {
	command := "agent.codex-auth.status"
	status := agent.CodexAuthStatusResult(c.options())
	if hasRequiredFailures(status.Diagnostics) {
		return rt.Fail(command, false, "Codex auth status has errors", status, status.Diagnostics)
	}
	return rt.Emit(report.New(command, true, false, false, "Codex auth status: "+status.AuthFile.AuthMode, status, status.Diagnostics))
}

func (c *AgentCodexAuthSaveCmd) Run(rt *appctx.Runtime) error {
	command := "agent.codex-auth.save"
	result, err := agent.SaveCodexAuth(c.options(), c.Mode)
	result.OperationReportPath, result.Diagnostics = writeAgentMutationReport(rt, command, c.ReportOut, result, err == nil)
	if err != nil {
		return rt.Fail(command, false, "could not save Codex auth snapshot", result, result.Diagnostics)
	}
	if hasErrorDiagnostics(result.Diagnostics, "operation_report") {
		return rt.Fail(command, false, "could not write Codex auth operation report", result, result.Diagnostics)
	}
	return rt.Emit(report.New(command, true, result.Changed, false, "saved Codex auth snapshot: "+c.Mode, result, result.Diagnostics))
}

func (c *AgentCodexAuthUseCmd) Run(rt *appctx.Runtime) error {
	command := "agent.codex-auth.use"
	result, err := agent.UseCodexAuth(c.options(), c.Mode)
	result.OperationReportPath, result.Diagnostics = writeAgentMutationReport(rt, command, c.ReportOut, result, err == nil)
	if err != nil {
		return rt.Fail(command, false, "could not switch Codex auth snapshot", result, result.Diagnostics)
	}
	if hasErrorDiagnostics(result.Diagnostics, "operation_report") {
		return rt.Fail(command, false, "could not write Codex auth operation report", result, result.Diagnostics)
	}
	return rt.Emit(report.New(command, true, result.Changed, false, "switched Codex auth snapshot: "+c.Mode, result, result.Diagnostics))
}

func emitSkillset(rt *appctx.Runtime, command string, result agent.SkillsetResult) error {
	ok := !hasRequiredFailures(result.Diagnostics)
	summary := fmt.Sprintf("skillset %s exited %d", result.Command, result.ExitCode)
	if !ok {
		return rt.Fail(command, result.DryRun, summary, result, result.Diagnostics)
	}
	return rt.Emit(report.New(command, true, false, result.DryRun, summary, result, result.Diagnostics))
}

func (c *AgentSkillsSyncCmd) writeReport(rt *appctx.Runtime, command string, result agent.SkillsetResult) (string, []report.Diagnostic) {
	diagnostics := append([]report.Diagnostic{}, result.Diagnostics...)
	path, err := rt.WriteOperationReport(report.OperationReportInput{
		Command:           command,
		OK:                !hasRequiredFailures(result.Diagnostics),
		Changed:           !c.DryRun && result.ExitCode == 0,
		DryRun:            c.DryRun,
		ReleaseEligible:   false,
		VerificationHints: []string{"configctl agent skills verify"},
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

func writeAgentMutationReport(rt *appctx.Runtime, command string, reportOut string, result agent.AuthMutationResult, ok bool) (string, []report.Diagnostic) {
	diagnostics := append([]report.Diagnostic{}, result.Diagnostics...)
	var touched []string
	if result.AuthFile.Path != "" {
		touched = append(touched, result.AuthFile.Path)
	}
	if result.Snapshot.Path != "" {
		touched = append(touched, result.Snapshot.Path)
	}
	var backups []string
	if result.BackupPath != "" {
		backups = append(backups, result.BackupPath)
	}
	path, err := rt.WriteOperationReport(report.OperationReportInput{
		Command:           command,
		OK:                ok,
		Changed:           result.Changed,
		ReleaseEligible:   false,
		TouchedPaths:      touched,
		Backups:           backups,
		VerificationHints: []string{"configctl agent codex-auth status"},
		Diagnostics:       result.Diagnostics,
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

func (c agentOptions) options() agent.Options {
	return agent.Options{
		PublicRepoDir:   c.PublicRepo,
		PrivateRepoDir:  c.PrivateRepo,
		HomeDir:         c.HomeDir,
		SkillsetBin:     c.SkillsetBin,
		SkillsetProfile: c.SkillsetProfile,
	}
}
