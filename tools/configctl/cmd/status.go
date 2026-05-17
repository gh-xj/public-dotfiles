package cmd

import (
	"context"

	appctx "configctl/internal/app"
	"configctl/internal/domain/controlplane"
	"configctl/internal/report"
	"configctl/internal/verify"
)

type StatusCmd struct {
	rootOptions
}

type VerifyCmd struct {
	rootOptions
	Profile string `name:"profile" enum:"default,full" default:"default" help:"verification profile to run"`
}

type rootOptions struct {
	Registry    string `name:"registry" help:"repo registry path" type:"path"`
	HomeDir     string `name:"home" help:"home directory to inspect" type:"path"`
	PublicRepo  string `name:"public-repo" help:"public-dotfiles repo path" type:"path"`
	PrivateRepo string `name:"private-repo" help:"private-config repo path" type:"path"`
}

func (c *StatusCmd) Run(rt *appctx.Runtime) error {
	command := "status"
	status, err := controlplane.Status(context.Background(), c.options())
	if err != nil {
		return rt.Fail(command, false, "could not inspect configctl status", status, status.Diagnostics)
	}
	return rt.Emit(report.New(command, true, false, false, controlplane.Summary(status), status, status.Diagnostics))
}

func (c *VerifyCmd) Run(rt *appctx.Runtime) error {
	command := "verify"
	profile, err := verify.ParseProfile(c.Profile)
	if err != nil {
		return rt.Fail(command, false, "unsupported verify profile", map[string]any{
			"profile": c.Profile,
		}, []report.Diagnostic{{
			Severity: "error",
			Code:     "verify.profile_invalid",
			Message:  err.Error(),
		}})
	}
	result := controlplane.Verify(context.Background(), c.options(), profile)
	if !result.OK {
		return rt.Fail(command, false, controlplane.VerifySummary(result), result, result.Diagnostics)
	}
	return rt.Emit(report.New(command, true, false, false, controlplane.VerifySummary(result), result, result.Diagnostics))
}

func (c rootOptions) options() controlplane.Options {
	return controlplane.Options{
		RegistryPath:   c.Registry,
		HomeDir:        c.HomeDir,
		PublicRepoDir:  c.PublicRepo,
		PrivateRepoDir: c.PrivateRepo,
	}
}
