package cmd

import (
	"context"

	appctx "configctl/internal/app"
	"configctl/internal/domain/packageaudit"
	"configctl/internal/report"
)

type PackageCmd struct {
	Status PackageStatusCmd `cmd:"" help:"summarize package ledgers and installed packages"`
	Audit  PackageAuditCmd  `cmd:"" help:"compare package ledgers with installed packages"`
	Verify PackageVerifyCmd `cmd:"" help:"verify package ledger inspection"`
}

type packageOptions struct {
	PublicRepo  string `name:"public-repo" help:"public-dotfiles repo path" type:"path"`
	PrivateRepo string `name:"private-repo" help:"private-config repo path" type:"path"`
}

type PackageStatusCmd struct {
	packageOptions
}

type PackageAuditCmd struct {
	packageOptions
}

type PackageVerifyCmd struct {
	packageOptions
}

func (c *PackageStatusCmd) Run(rt *appctx.Runtime) error {
	command := "package.status"
	status := packageaudit.Status(context.Background(), c.options())
	if hasPackageInspectionErrors(status.Diagnostics) {
		return rt.Fail(command, false, "could not inspect package ledgers", status, status.Diagnostics)
	}
	return rt.Emit(report.New(command, true, false, false, packageaudit.Summary(status), status, status.Diagnostics))
}

func (c *PackageAuditCmd) Run(rt *appctx.Runtime) error {
	command := "package.audit"
	status := packageaudit.Status(context.Background(), c.options())
	if hasPackageInspectionErrors(status.Diagnostics) {
		return rt.Fail(command, false, "could not audit package ledgers", status.Audit, status.Diagnostics)
	}
	return rt.Emit(report.New(command, true, false, false, packageaudit.AuditSummary(status.Audit), status.Audit, status.Diagnostics))
}

func (c *PackageVerifyCmd) Run(rt *appctx.Runtime) error {
	command := "package.verify"
	status, failures := packageaudit.Verify(context.Background(), c.options())
	if len(failures) > 0 {
		return rt.Fail(command, false, packageaudit.VerifySummary(failures), status, status.Diagnostics)
	}
	return rt.Emit(report.New(command, true, false, false, packageaudit.VerifySummary(failures), status, status.Diagnostics))
}

func (c packageOptions) options() packageaudit.Options {
	return packageaudit.Options{
		PublicRepoDir:  c.PublicRepo,
		PrivateRepoDir: c.PrivateRepo,
	}
}

func hasPackageInspectionErrors(diagnostics []report.Diagnostic) bool {
	for _, diagnostic := range diagnostics {
		if diagnostic.Severity == "error" {
			return true
		}
	}
	return false
}
