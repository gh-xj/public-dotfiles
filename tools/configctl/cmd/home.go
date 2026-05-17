package cmd

import (
	"fmt"
	"strings"

	"configctl/internal/domain/home"
	"configctl/internal/paths"
	"configctl/internal/report"
)

type HomeCmd struct {
	Status  HomeStatusCmd  `cmd:"" help:"summarize repo-backed home topology"`
	Resolve HomeResolveCmd `cmd:"" help:"resolve a live home path to its owning repo entry"`
	Plan    HomePlanCmd    `cmd:"" help:"preview home topology actions without mutating"`
	Verify  HomeVerifyCmd  `cmd:"" help:"verify home paths resolve to their owner repos"`
}

type homeOptions struct {
	HomeDir     string `name:"home" help:"home directory to inspect" type:"path"`
	PublicRepo  string `name:"public-repo" help:"public-dotfiles repo path" type:"path"`
	PrivateRepo string `name:"private-repo" help:"private-config repo path" type:"path"`
	PublicOnly  bool   `name:"public-only" help:"ignore private overlay manifest"`
}

type HomeStatusCmd struct {
	homeOptions
}

type HomeResolveCmd struct {
	homeOptions
	Path string `arg:"" help:"home-relative or absolute path to resolve"`
}

type HomePlanCmd struct {
	homeOptions
	Mode string `name:"mode" enum:"symlink,copy" default:"symlink" help:"override link/copy entries for the preview"`
}

type HomeVerifyCmd struct {
	homeOptions
	All bool `name:"all" help:"verify every manifest entry instead of the representative ownership set"`
}

func (c *HomeStatusCmd) Run(rt *Runtime) error {
	command := "home.status"
	status, err := home.Status(c.options(""))
	if err != nil {
		return rt.Fail(command, false, "could not inspect home topology", map[string]any{}, []report.Diagnostic{{
			Severity: "error",
			Code:     "home.status_failed",
			Message:  err.Error(),
		}})
	}
	return rt.Emit(report.New(command, true, false, false, homeStatusSummary(status), status, status.Diagnostics))
}

func (c *HomeResolveCmd) Run(rt *Runtime) error {
	command := "home.resolve"
	result, err := home.Resolve(c.Path, c.options(""))
	if err != nil {
		return rt.Fail(command, false, "could not resolve home path", map[string]any{
			"input": c.Path,
		}, []report.Diagnostic{{
			Severity: "error",
			Code:     "home.resolve_failed",
			Message:  err.Error(),
		}})
	}
	summary := "unmanaged home path: " + result.TargetPath
	if result.Owner != "" {
		summary = fmt.Sprintf("%s is managed by %s", result.TargetPath, result.Owner)
	}
	return rt.Emit(report.New(command, true, false, false, summary, result, result.Diagnostics))
}

func (c *HomePlanCmd) Run(rt *Runtime) error {
	command := "home.plan"
	status, err := home.Status(c.options(c.Mode))
	if err != nil {
		return rt.Fail(command, true, "could not plan home topology", map[string]any{}, []report.Diagnostic{{
			Severity: "error",
			Code:     "home.plan_failed",
			Message:  err.Error(),
		}})
	}
	return rt.Emit(report.New(command, true, false, true, homePlanSummary(status), status, status.Diagnostics))
}

func (c *HomeVerifyCmd) Run(rt *Runtime) error {
	command := "home.verify"
	opts := c.options("")
	opts.VerifyAll = c.All
	status, failures, err := home.Verify(opts)
	if err != nil {
		return rt.Fail(command, false, "could not verify home topology", map[string]any{}, []report.Diagnostic{{
			Severity: "error",
			Code:     "home.verify_failed",
			Message:  err.Error(),
		}})
	}
	if len(failures) > 0 {
		diagnostics := append([]report.Diagnostic{}, status.Diagnostics...)
		diagnostics = append(diagnostics, failures...)
		return rt.Fail(command, false, fmt.Sprintf("home topology verification failed: %d issue(s)", len(failures)), status, diagnostics)
	}
	return rt.Emit(report.New(command, true, false, false, homeVerifySummary(status, c.All), status, status.Diagnostics))
}

func (c homeOptions) options(modeOverride string) home.Options {
	return home.Options{
		HomeDir:        paths.Expand(c.HomeDir),
		PublicRepoDir:  paths.Expand(c.PublicRepo),
		PrivateRepoDir: paths.Expand(c.PrivateRepo),
		PublicOnly:     c.PublicOnly,
		ModeOverride:   parseHomeMode(modeOverride),
	}
}

func parseHomeMode(mode string) home.Mode {
	switch mode {
	case "copy":
		return home.ModeCopy
	case "symlink":
		return home.ModeLink
	default:
		return ""
	}
}

func homeStatusSummary(status home.StatusResult) string {
	return fmt.Sprintf("home topology: %d entries, %d linked, %d missing, %d occupied, %d wrong links",
		len(status.Entries),
		status.Counts["linked"],
		status.Counts["missing"],
		status.Counts["occupied"],
		status.Counts["wrong_link"],
	)
}

func homePlanSummary(status home.StatusResult) string {
	actions := map[string]int{}
	for _, entry := range status.Entries {
		actions[entry.Action]++
	}
	parts := make([]string, 0, len(actions))
	for _, key := range []string{"skip", "link", "copy", "merge", "backup_then_link", "fix_manifest_or_source"} {
		if actions[key] > 0 {
			parts = append(parts, fmt.Sprintf("%s=%d", key, actions[key]))
		}
	}
	if len(parts) == 0 {
		parts = append(parts, "no actions")
	}
	return "home plan dry-run: " + strings.Join(parts, ", ")
}

func homeVerifySummary(status home.StatusResult, all bool) string {
	scope := "representative"
	if all {
		scope = "manifest"
	}
	return fmt.Sprintf("home topology verified: %d %s entries", len(status.Entries), scope)
}
