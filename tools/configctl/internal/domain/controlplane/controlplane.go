package controlplane

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

	gitadapter "configctl/internal/adapters/git"
	"configctl/internal/domain/agent"
	"configctl/internal/domain/home"
	"configctl/internal/domain/repo"
	"configctl/internal/domain/workspace"
	"configctl/internal/report"
	"configctl/internal/verify"
)

type Options struct {
	RegistryPath   string
	HomeDir        string
	PublicRepoDir  string
	PrivateRepoDir string
	Git            gitadapter.Inspector
}

type StatusResult struct {
	Registry    RegistryStatus         `json:"registry"`
	Repos       []RepoStatus           `json:"repos"`
	Home        home.StatusResult      `json:"home"`
	Workspace   workspace.StatusResult `json:"workspace"`
	Checks      verify.Counts          `json:"checks"`
	Diagnostics []report.Diagnostic    `json:"diagnostics"`
}

type RegistryStatus struct {
	Path    string             `json:"path"`
	Loaded  bool               `json:"loaded"`
	Overlay repo.OverlayStatus `json:"overlay"`
	Repos   int                `json:"repos"`
}

type RepoStatus struct {
	Name        string                   `json:"name"`
	Owner       string                   `json:"owner"`
	Path        string                   `json:"path"`
	Required    bool                     `json:"required"`
	Exists      bool                     `json:"exists"`
	Git         *gitadapter.DirtySummary `json:"git,omitempty"`
	Diagnostics []report.Diagnostic      `json:"diagnostics,omitempty"`
}

func Status(ctx context.Context, opts Options) (StatusResult, error) {
	registryPath, err := resolveRegistryPath(opts.RegistryPath)
	if err != nil {
		return StatusResult{}, err
	}
	registry, diagnostics, err := repo.LoadRegistry(registryPath)
	result := StatusResult{
		Registry: RegistryStatus{
			Path: registryPath,
		},
		Diagnostics: append([]report.Diagnostic{}, diagnostics...),
	}
	if err != nil {
		return result, err
	}
	result.Registry.Loaded = true
	result.Registry.Overlay = registry.Overlay
	result.Registry.Repos = len(registry.Repos)
	result.Repos = inspectRepos(ctx, registry.Repos, gitInspector(opts.Git))

	homeStatus, err := home.Status(homeOptionsFromRegistry(opts, registry.Repos))
	if err != nil {
		result.Diagnostics = append(result.Diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "controlplane.home_status_failed",
			Message:  err.Error(),
		})
		return result, err
	}
	result.Home = homeStatus
	result.Diagnostics = append(result.Diagnostics, homeStatus.Diagnostics...)
	workspaceStatus, err := workspace.Status(workspace.Options{})
	if err == nil {
		result.Workspace = workspaceStatus
		result.Diagnostics = append(result.Diagnostics, workspaceStatus.Diagnostics...)
	} else {
		result.Diagnostics = append(result.Diagnostics, workspaceStatus.Diagnostics...)
	}

	verifyResult := Verify(ctx, opts, verify.ProfileDefault)
	result.Checks = verifyResult.Counts
	result.Diagnostics = append(result.Diagnostics, repoDiagnostics(result.Repos)...)
	return result, nil
}

func Verify(ctx context.Context, opts Options, profile verify.Profile) verify.Result {
	runner := verify.Runner{Checks: []verify.Check{
		registryCheck(opts),
		homeCheck(opts, profile),
		workspaceCheck(),
		agentCheck(),
	}}
	return runner.Run(ctx, profile)
}

func Summary(status StatusResult) string {
	dirtyRepos := 0
	for _, repoStatus := range status.Repos {
		if repoStatus.Git == nil {
			continue
		}
		if repoStatus.Git.Changed+repoStatus.Git.Staged+repoStatus.Git.Untracked > 0 {
			dirtyRepos++
		}
	}
	return fmt.Sprintf("configctl status: %d repos, %d home entries, %d dirty repos, %d/%d checks passing",
		len(status.Repos),
		len(status.Home.Entries),
		dirtyRepos,
		status.Checks.Passed,
		status.Checks.Total,
	)
}

func workspaceCheck() verify.Check {
	return verify.Check{
		ID:       "workspace.verify",
		Name:     "workspace links",
		Required: true,
		Run: func(_ context.Context) verify.CheckResult {
			status, failures, err := workspace.Verify(workspace.Options{})
			if err != nil {
				return verifyFailure(err, "workspace.verify_failed", "could not verify workspace links", "")
			}
			diagnostics := append([]report.Diagnostic{}, status.Diagnostics...)
			diagnostics = append(diagnostics, failures...)
			if diagnosticsHaveErrors(failures) {
				return verify.CheckResult{
					OK:          false,
					Summary:     fmt.Sprintf("workspace links failed: %d issue(s)", len(failures)),
					Diagnostics: diagnostics,
				}
			}
			return verify.CheckResult{
				OK:          true,
				Summary:     fmt.Sprintf("workspace links verified: %d workspace(s)", len(status.Workspaces)),
				Diagnostics: diagnostics,
			}
		},
	}
}

func agentCheck() verify.Check {
	return verify.Check{
		ID:       "agent.verify",
		Name:     "agent topology",
		Required: true,
		Run: func(_ context.Context) verify.CheckResult {
			status, failures, err := agent.Verify(agent.Options{})
			if err != nil {
				return verifyFailure(err, "agent.verify_failed", "could not verify agent topology", "")
			}
			if len(failures) > 0 {
				return verify.CheckResult{
					OK:          false,
					Summary:     fmt.Sprintf("agent topology failed: %d issue(s)", len(failures)),
					Diagnostics: status.Diagnostics,
				}
			}
			return verify.CheckResult{
				OK:          true,
				Summary:     "agent topology verified",
				Diagnostics: status.Diagnostics,
			}
		},
	}
}

func VerifySummary(result verify.Result) string {
	if result.OK {
		return fmt.Sprintf("configctl verify %s: %d/%d checks passing", result.Profile, result.Counts.Passed, result.Counts.Total)
	}
	return fmt.Sprintf("configctl verify %s failed: %d required check(s) failed", result.Profile, result.Counts.RequiredFailed)
}

func registryCheck(opts Options) verify.Check {
	return verify.Check{
		ID:       "repo.registry",
		Name:     "repo registry",
		Required: true,
		Run: func(_ context.Context) verify.CheckResult {
			registryPath, err := resolveRegistryPath(opts.RegistryPath)
			if err != nil {
				return verifyFailure(err, "repo.registry_not_found", "repo registry not found", "")
			}
			_, diagnostics, err := repo.LoadRegistry(registryPath)
			if err != nil {
				return verify.CheckResult{
					OK:          false,
					Summary:     "repo registry invalid",
					Diagnostics: diagnostics,
				}
			}
			return verify.CheckResult{OK: true, Summary: "repo registry loaded", Diagnostics: diagnostics}
		},
	}
}

func homeCheck(opts Options, profile verify.Profile) verify.Check {
	return verify.Check{
		ID:       "home.verify",
		Name:     "home topology",
		Required: true,
		Run: func(_ context.Context) verify.CheckResult {
			registryPath, err := resolveRegistryPath(opts.RegistryPath)
			if err != nil {
				return verifyFailure(err, "home.registry_not_found", "repo registry not found", "")
			}
			registry, diagnostics, err := repo.LoadRegistry(registryPath)
			if err != nil {
				return verify.CheckResult{OK: false, Summary: "could not load home repo registry", Diagnostics: diagnostics}
			}
			homeOpts := homeOptionsFromRegistry(opts, registry.Repos)
			homeOpts.VerifyAll = profile == verify.ProfileFull
			status, failures, err := home.Verify(homeOpts)
			if err != nil {
				return verifyFailure(err, "home.verify_failed", "could not verify home topology", "")
			}
			allDiagnostics := append([]report.Diagnostic{}, status.Diagnostics...)
			allDiagnostics = append(allDiagnostics, failures...)
			if len(failures) > 0 {
				return verify.CheckResult{
					OK:          false,
					Summary:     fmt.Sprintf("home topology failed: %d issue(s)", len(failures)),
					Diagnostics: allDiagnostics,
				}
			}
			scope := "representative"
			if profile == verify.ProfileFull {
				scope = "manifest"
			}
			return verify.CheckResult{
				OK:          true,
				Summary:     fmt.Sprintf("home topology verified: %d %s entries", len(status.Entries), scope),
				Diagnostics: allDiagnostics,
			}
		},
	}
}

func inspectRepos(ctx context.Context, definitions []repo.Definition, inspector gitadapter.Inspector) []RepoStatus {
	statuses := make([]RepoStatus, 0, len(definitions))
	for _, definition := range definitions {
		status := RepoStatus{
			Name:     definition.Name,
			Owner:    definition.Owner,
			Path:     definition.Path,
			Required: definition.Required,
		}
		info, err := os.Stat(definition.Path)
		if err != nil {
			code := "controlplane.repo_missing"
			severity := "warning"
			if definition.Required {
				severity = "error"
			}
			status.Diagnostics = append(status.Diagnostics, report.Diagnostic{
				Severity: severity,
				Code:     code,
				Message:  "managed repo path is missing",
				Path:     definition.Path,
			})
			statuses = append(statuses, status)
			continue
		}
		status.Exists = info.IsDir()
		if !status.Exists {
			status.Diagnostics = append(status.Diagnostics, report.Diagnostic{
				Severity: "error",
				Code:     "controlplane.repo_not_directory",
				Message:  "managed repo path is not a directory",
				Path:     definition.Path,
			})
			statuses = append(statuses, status)
			continue
		}
		dirty, err := inspector.DirtySummary(ctx, definition.Path)
		if err != nil {
			status.Diagnostics = append(status.Diagnostics, report.Diagnostic{
				Severity: "warning",
				Code:     "controlplane.git_status_failed",
				Message:  err.Error(),
				Path:     definition.Path,
			})
		} else {
			status.Git = &dirty
		}
		statuses = append(statuses, status)
	}
	return statuses
}

func homeOptionsFromRegistry(opts Options, repos []repo.Definition) home.Options {
	homeOpts := home.Options{
		HomeDir:        opts.HomeDir,
		PublicRepoDir:  opts.PublicRepoDir,
		PrivateRepoDir: opts.PrivateRepoDir,
	}
	for _, definition := range repos {
		switch definition.Name {
		case "public-dotfiles":
			if homeOpts.PublicRepoDir == "" {
				homeOpts.PublicRepoDir = definition.Path
			}
		case "private-config":
			if homeOpts.PrivateRepoDir == "" {
				homeOpts.PrivateRepoDir = definition.Path
			}
		}
	}
	return homeOpts
}

func repoDiagnostics(statuses []RepoStatus) []report.Diagnostic {
	var diagnostics []report.Diagnostic
	for _, status := range statuses {
		diagnostics = append(diagnostics, status.Diagnostics...)
	}
	return diagnostics
}

func diagnosticsHaveErrors(diagnostics []report.Diagnostic) bool {
	for _, diagnostic := range diagnostics {
		if diagnostic.Severity == "error" {
			return true
		}
	}
	return false
}

func resolveRegistryPath(explicit string) (string, error) {
	if explicit != "" {
		if filepath.IsAbs(explicit) {
			return filepath.Clean(explicit), nil
		}
		return filepath.Abs(explicit)
	}
	return repo.DefaultRegistryPath()
}

func gitInspector(inspector gitadapter.Inspector) gitadapter.Inspector {
	if inspector != nil {
		return inspector
	}
	return gitadapter.CLIInspector{}
}

func verifyFailure(err error, code string, summary string, path string) verify.CheckResult {
	return verify.CheckResult{
		OK:      false,
		Summary: summary,
		Diagnostics: []report.Diagnostic{{
			Severity: "error",
			Code:     code,
			Message:  err.Error(),
			Path:     path,
		}},
	}
}
