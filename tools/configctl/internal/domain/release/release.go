package release

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"configctl/internal/adapters/process"
	"configctl/internal/domain/repo"
	"configctl/internal/report"
)

type CaptureOptions struct {
	RegistryPath     string
	Paths            []string
	OperationReports []string
	Message          string
	Apply            bool
	Push             bool
	RepoRoots        map[string]string
	Runner           process.Runner
}

type CaptureResult struct {
	DryRun               bool                `json:"dry_run"`
	Apply                bool                `json:"apply"`
	Push                 bool                `json:"push"`
	Message              string              `json:"message"`
	Inputs               CaptureInputs       `json:"inputs"`
	Repos                []RepoResult        `json:"repos"`
	TouchedPaths         []string            `json:"touched_paths"`
	VerificationCommands []VerificationPlan  `json:"verification_commands"`
	OperationReportPath  string              `json:"operation_report_path,omitempty"`
	Diagnostics          []report.Diagnostic `json:"diagnostics"`
}

type CaptureInputs struct {
	Paths            []string            `json:"paths"`
	OperationReports []ReportInputStatus `json:"operation_reports"`
}

type ReportInputStatus struct {
	Path            string              `json:"path"`
	SchemaVersion   string              `json:"schema_version,omitempty"`
	Command         string              `json:"command,omitempty"`
	OK              bool                `json:"ok"`
	Changed         bool                `json:"changed"`
	DryRun          bool                `json:"dry_run"`
	ReleaseEligible bool                `json:"release_eligible"`
	TouchedPaths    []string            `json:"touched_paths"`
	Diagnostics     []report.Diagnostic `json:"diagnostics"`
}

type RepoResult struct {
	Name                 string              `json:"name"`
	Root                 string              `json:"root"`
	Branch               string              `json:"branch,omitempty"`
	DeclaredPaths        []string            `json:"declared_paths"`
	StagedFiles          []string            `json:"staged_files"`
	CachedDiffInspected  bool                `json:"cached_diff_inspected"`
	CommitHash           string              `json:"commit_hash,omitempty"`
	Pushed               bool                `json:"pushed"`
	VerificationCommands []VerificationPlan  `json:"verification_commands"`
	Diagnostics          []report.Diagnostic `json:"diagnostics"`
}

type VerificationPlan struct {
	Repo     string   `json:"repo"`
	Phase    string   `json:"phase"`
	Command  string   `json:"command"`
	Args     []string `json:"args"`
	Dir      string   `json:"dir"`
	Ran      bool     `json:"ran"`
	ExitCode int      `json:"exit_code,omitempty"`
}

type repoRoot struct {
	Name string
	Path string
}

type releasePath struct {
	RepoName string
	Root     string
	Abs      string
	Rel      string
	Source   string
}

var operationSchemaPattern = regexp.MustCompile(`^configctl\.operation\.v([0-9]+)(?:[.-].*)?$`)

func Capture(ctx context.Context, opts CaptureOptions) (CaptureResult, error) {
	resolved := resolveOptions(opts)
	result := CaptureResult{
		DryRun:  !resolved.Apply,
		Apply:   resolved.Apply,
		Push:    resolved.Push,
		Message: strings.TrimSpace(resolved.Message),
		Inputs: CaptureInputs{
			Paths: append([]string{}, resolved.Paths...),
		},
	}
	if resolved.Push && !resolved.Apply {
		return failResult(result, "release.push_requires_apply", "--push requires --apply", "")
	}
	if resolved.Apply && result.Message == "" {
		return failResult(result, "release.message_required", "--message is required with --apply", "")
	}
	if len(resolved.Paths) == 0 && len(resolved.OperationReports) == 0 {
		return failResult(result, "release.no_paths", "release capture requires --path or --operation-report", "")
	}

	roots, diagnostics, err := resolveRepoRoots(resolved)
	result.Diagnostics = append(result.Diagnostics, diagnostics...)
	if err != nil {
		return result, err
	}

	var paths []releasePath
	for _, path := range resolved.Paths {
		releasePath, err := resolveReleasePath(path, "capture", roots)
		if err != nil {
			result.Diagnostics = append(result.Diagnostics, report.Diagnostic{
				Severity: "error",
				Code:     "release.path_outside_repo",
				Message:  err.Error(),
				Path:     path,
			})
			continue
		}
		paths = append(paths, releasePath)
	}
	for _, reportPath := range resolved.OperationReports {
		status, touched, diagnostics := loadReportPaths(reportPath, roots)
		result.Inputs.OperationReports = append(result.Inputs.OperationReports, status)
		result.Diagnostics = append(result.Diagnostics, diagnostics...)
		paths = append(paths, touched...)
	}
	if hasErrors(result.Diagnostics) {
		return result, fmt.Errorf("release capture input validation failed")
	}

	paths = uniqueReleasePaths(paths)
	if len(paths) == 0 {
		return failResult(result, "release.no_touched_paths", "release capture has no touched paths", "")
	}
	for _, item := range paths {
		result.TouchedPaths = append(result.TouchedPaths, item.Abs)
	}
	sort.Strings(result.TouchedPaths)

	groups := groupByRepo(paths)
	for _, group := range groups {
		repoResult := captureRepo(ctx, resolved, group)
		result.Repos = append(result.Repos, repoResult)
		result.Diagnostics = append(result.Diagnostics, repoResult.Diagnostics...)
		result.VerificationCommands = append(result.VerificationCommands, repoResult.VerificationCommands...)
	}
	if hasErrors(result.Diagnostics) {
		return result, fmt.Errorf("release capture failed")
	}
	return result, nil
}

func captureRepo(ctx context.Context, opts CaptureOptions, paths []releasePath) RepoResult {
	first := paths[0]
	result := RepoResult{
		Name:          first.RepoName,
		Root:          first.Root,
		DeclaredPaths: rels(paths),
	}
	result.Branch = gitOutput(ctx, opts.Runner, first.Root, []string{"branch", "--show-current"})
	result.VerificationCommands = verificationPlan(first.RepoName, first.Root, opts.Apply)
	if !opts.Apply {
		return result
	}
	for _, plan := range result.VerificationCommands {
		if plan.Phase != "pre-stage" {
			continue
		}
		ran := runPlan(ctx, opts.Runner, plan)
		result.VerificationCommands = replacePlan(result.VerificationCommands, ran)
		if ran.ExitCode != 0 {
			result.Diagnostics = append(result.Diagnostics, planDiagnostic("release.verify_failed", ran))
			return result
		}
	}
	if staged := gitLines(ctx, opts.Runner, first.Root, []string{"diff", "--cached", "--name-only"}); len(staged) > 0 {
		result.Diagnostics = append(result.Diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "release.preexisting_staged_changes",
			Message:  "repo has staged changes before release capture",
			Path:     first.Root,
		})
		return result
	}
	args := append([]string{"add", "--"}, result.DeclaredPaths...)
	if code := gitExitCode(ctx, opts.Runner, first.Root, args); code != 0 {
		result.Diagnostics = append(result.Diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "release.git_add_failed",
			Message:  fmt.Sprintf("git add exited %d", code),
			Path:     first.Root,
		})
		return result
	}
	result.StagedFiles = gitLines(ctx, opts.Runner, first.Root, []string{"diff", "--cached", "--name-only"})
	result.CachedDiffInspected = true
	if !stagedSubset(result.StagedFiles, result.DeclaredPaths) {
		result.Diagnostics = append(result.Diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "release.staged_path_scope_failed",
			Message:  "cached diff includes paths outside release capture scope",
			Path:     first.Root,
		})
		return result
	}
	if len(result.StagedFiles) == 0 {
		result.Diagnostics = append(result.Diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "release.no_staged_changes",
			Message:  "release capture produced no staged changes",
			Path:     first.Root,
		})
		return result
	}
	for _, plan := range result.VerificationCommands {
		if plan.Phase != "post-stage" {
			continue
		}
		ran := runPlan(ctx, opts.Runner, plan)
		result.VerificationCommands = replacePlan(result.VerificationCommands, ran)
		if ran.ExitCode != 0 {
			result.Diagnostics = append(result.Diagnostics, planDiagnostic("release.verify_failed", ran))
			return result
		}
	}
	commitArgs := []string{"commit", "-m", opts.Message}
	if code := gitExitCode(ctx, opts.Runner, first.Root, commitArgs); code != 0 {
		result.Diagnostics = append(result.Diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "release.git_commit_failed",
			Message:  fmt.Sprintf("git commit exited %d", code),
			Path:     first.Root,
		})
		return result
	}
	result.CommitHash = gitOutput(ctx, opts.Runner, first.Root, []string{"rev-parse", "HEAD"})
	if opts.Push {
		pushTarget := result.Branch
		if pushTarget == "" {
			pushTarget = "HEAD"
		}
		if code := gitExitCode(ctx, opts.Runner, first.Root, []string{"push", "origin", pushTarget}); code != 0 {
			result.Diagnostics = append(result.Diagnostics, report.Diagnostic{
				Severity: "error",
				Code:     "release.git_push_failed",
				Message:  fmt.Sprintf("git push exited %d", code),
				Path:     first.Root,
			})
			return result
		}
		result.Pushed = true
	}
	return result
}

func loadReportPaths(path string, roots []repoRoot) (ReportInputStatus, []releasePath, []report.Diagnostic) {
	abs, err := filepath.Abs(expandHome(path))
	status := ReportInputStatus{Path: path}
	if err != nil {
		return status, nil, []report.Diagnostic{{Severity: "error", Code: "release.report_path_invalid", Message: err.Error(), Path: path}}
	}
	status.Path = abs
	data, err := os.ReadFile(abs)
	if err != nil {
		return status, nil, []report.Diagnostic{{Severity: "error", Code: "release.report_read_failed", Message: err.Error(), Path: abs}}
	}
	var operation report.OperationReport
	if err := json.Unmarshal(data, &operation); err != nil {
		return status, nil, []report.Diagnostic{{Severity: "error", Code: "release.report_parse_failed", Message: err.Error(), Path: abs}}
	}
	status.SchemaVersion = operation.SchemaVersion
	status.Command = operation.Command
	status.OK = operation.OK
	status.Changed = operation.Changed
	status.DryRun = operation.DryRun
	status.ReleaseEligible = operation.ReleaseEligible
	status.TouchedPaths = append([]string{}, operation.TouchedPaths...)
	if !sameOperationMajor(operation.SchemaVersion, report.OperationReportSchemaVersion) {
		status.Diagnostics = append(status.Diagnostics, report.Diagnostic{Severity: "error", Code: "release.report_schema_incompatible", Message: "operation report schema is not same-major compatible", Path: abs})
	}
	if !operation.OK {
		status.Diagnostics = append(status.Diagnostics, report.Diagnostic{Severity: "error", Code: "release.report_not_ok", Message: "operation report did not complete successfully", Path: abs})
	}
	if operation.DryRun {
		status.Diagnostics = append(status.Diagnostics, report.Diagnostic{Severity: "error", Code: "release.report_dry_run", Message: "dry-run operation report is not release eligible", Path: abs})
	}
	if !operation.Changed {
		status.Diagnostics = append(status.Diagnostics, report.Diagnostic{Severity: "error", Code: "release.report_unchanged", Message: "operation report has no changed paths", Path: abs})
	}
	if !operation.ReleaseEligible {
		status.Diagnostics = append(status.Diagnostics, report.Diagnostic{Severity: "error", Code: "release.report_not_release_eligible", Message: "operation report is not release eligible", Path: abs})
	}
	if len(operation.TouchedPaths) == 0 {
		status.Diagnostics = append(status.Diagnostics, report.Diagnostic{Severity: "error", Code: "release.report_no_touched_paths", Message: "operation report has no touched paths", Path: abs})
	}
	if len(status.Diagnostics) > 0 {
		return status, nil, status.Diagnostics
	}
	var paths []releasePath
	var diagnostics []report.Diagnostic
	for _, touched := range operation.TouchedPaths {
		item, err := resolveReleasePath(touched, "operation-report:"+abs, roots)
		if err != nil {
			diagnostics = append(diagnostics, report.Diagnostic{Severity: "error", Code: "release.report_path_outside_repo", Message: err.Error(), Path: touched})
			continue
		}
		paths = append(paths, item)
	}
	status.Diagnostics = append(status.Diagnostics, diagnostics...)
	return status, paths, diagnostics
}

func resolveRepoRoots(opts CaptureOptions) ([]repoRoot, []report.Diagnostic, error) {
	if len(opts.RepoRoots) > 0 {
		return repoRootsFromMap(opts.RepoRoots), nil, nil
	}
	registryPath := opts.RegistryPath
	if registryPath == "" {
		var err error
		registryPath, err = repo.DefaultRegistryPath()
		if err != nil {
			return nil, []report.Diagnostic{{Severity: "error", Code: "release.registry_not_found", Message: err.Error()}}, err
		}
	}
	registry, diagnostics, err := repo.LoadRegistry(registryPath)
	if err != nil {
		return nil, diagnostics, err
	}
	roots := make([]repoRoot, 0, len(registry.Repos))
	for _, definition := range registry.Repos {
		roots = append(roots, repoRoot{Name: definition.Name, Path: definition.Path})
	}
	sort.Slice(roots, func(i, j int) bool {
		return len(roots[i].Path) > len(roots[j].Path)
	})
	return roots, diagnostics, nil
}

func repoRootsFromMap(values map[string]string) []repoRoot {
	roots := make([]repoRoot, 0, len(values))
	for name, path := range values {
		roots = append(roots, repoRoot{Name: name, Path: filepath.Clean(path)})
	}
	sort.Slice(roots, func(i, j int) bool {
		return len(roots[i].Path) > len(roots[j].Path)
	})
	return roots
}

func resolveReleasePath(path string, source string, roots []repoRoot) (releasePath, error) {
	abs, err := filepath.Abs(expandHome(path))
	if err != nil {
		return releasePath{}, err
	}
	abs = filepath.Clean(abs)
	for _, root := range roots {
		rel, err := filepath.Rel(root.Path, abs)
		if err != nil {
			continue
		}
		if rel == "." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) || rel == ".." || filepath.IsAbs(rel) {
			continue
		}
		return releasePath{RepoName: root.Name, Root: root.Path, Abs: abs, Rel: filepath.ToSlash(rel), Source: source}, nil
	}
	return releasePath{}, fmt.Errorf("%s is outside managed repos", path)
}

func verificationPlan(repoName string, root string, apply bool) []VerificationPlan {
	var plans []VerificationPlan
	if fileExists(filepath.Join(root, "Taskfile.yml")) {
		plans = append(plans, VerificationPlan{Repo: repoName, Phase: "pre-stage", Command: "task", Args: []string{"dotfiles:verify"}, Dir: root})
		plans = append(plans, VerificationPlan{Repo: repoName, Phase: "post-stage", Command: "git", Args: []string{"diff", "--cached", "--check"}, Dir: root})
		plans = append(plans, VerificationPlan{Repo: repoName, Phase: "post-stage", Command: "task", Args: []string{"secrets:staged"}, Dir: root})
	} else {
		plans = append(plans, VerificationPlan{Repo: repoName, Phase: "pre-stage", Command: "git", Args: []string{"diff", "--check"}, Dir: root})
		plans = append(plans, VerificationPlan{Repo: repoName, Phase: "post-stage", Command: "git", Args: []string{"diff", "--cached", "--check"}, Dir: root})
	}
	if !apply {
		return plans
	}
	return plans
}

func runPlan(ctx context.Context, runner process.Runner, plan VerificationPlan) VerificationPlan {
	result, err := runner.Run(ctx, process.Invocation{Command: plan.Command, Args: plan.Args, Dir: plan.Dir})
	plan.Ran = true
	if err != nil {
		plan.ExitCode = -1
		return plan
	}
	plan.ExitCode = result.ExitCode
	return plan
}

func replacePlan(plans []VerificationPlan, replacement VerificationPlan) []VerificationPlan {
	out := append([]VerificationPlan{}, plans...)
	for i, plan := range out {
		if plan.Repo == replacement.Repo && plan.Phase == replacement.Phase && plan.Command == replacement.Command && strings.Join(plan.Args, "\x00") == strings.Join(replacement.Args, "\x00") {
			out[i] = replacement
			return out
		}
	}
	return out
}

func planDiagnostic(code string, plan VerificationPlan) report.Diagnostic {
	return report.Diagnostic{
		Severity: "error",
		Code:     code,
		Message:  fmt.Sprintf("%s %s exited %d", plan.Command, strings.Join(plan.Args, " "), plan.ExitCode),
		Path:     plan.Dir,
	}
}

func gitExitCode(ctx context.Context, runner process.Runner, root string, args []string) int {
	result, err := runner.Run(ctx, process.Invocation{Command: "git", Args: append([]string{"-C", root}, args...)})
	if err != nil {
		return -1
	}
	return result.ExitCode
}

func gitOutput(ctx context.Context, runner process.Runner, root string, args []string) string {
	result, err := runner.Run(ctx, process.Invocation{Command: "git", Args: append([]string{"-C", root}, args...)})
	if err != nil || result.ExitCode != 0 {
		return ""
	}
	return strings.TrimSpace(result.Stdout)
}

func gitLines(ctx context.Context, runner process.Runner, root string, args []string) []string {
	return splitLines(gitOutput(ctx, runner, root, args))
}

func groupByRepo(paths []releasePath) [][]releasePath {
	byRepo := map[string][]releasePath{}
	for _, item := range paths {
		byRepo[item.Root] = append(byRepo[item.Root], item)
	}
	var roots []string
	for root := range byRepo {
		roots = append(roots, root)
	}
	sort.Strings(roots)
	groups := make([][]releasePath, 0, len(roots))
	for _, root := range roots {
		sort.Slice(byRepo[root], func(i, j int) bool { return byRepo[root][i].Rel < byRepo[root][j].Rel })
		groups = append(groups, byRepo[root])
	}
	return groups
}

func rels(paths []releasePath) []string {
	out := make([]string, 0, len(paths))
	for _, item := range paths {
		out = append(out, item.Rel)
	}
	sort.Strings(out)
	return out
}

func uniqueReleasePaths(paths []releasePath) []releasePath {
	seen := map[string]releasePath{}
	for _, item := range paths {
		seen[item.Root+"\x00"+item.Rel] = item
	}
	out := make([]releasePath, 0, len(seen))
	for _, item := range seen {
		out = append(out, item)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Root != out[j].Root {
			return out[i].Root < out[j].Root
		}
		return out[i].Rel < out[j].Rel
	})
	return out
}

func stagedSubset(staged []string, allowed []string) bool {
	allowedSet := map[string]struct{}{}
	for _, value := range allowed {
		allowedSet[filepath.ToSlash(value)] = struct{}{}
	}
	for _, value := range staged {
		if _, ok := allowedSet[filepath.ToSlash(value)]; !ok {
			return false
		}
	}
	return true
}

func sameOperationMajor(candidate string, current string) bool {
	candidateMajor := operationMajor(candidate)
	currentMajor := operationMajor(current)
	return candidateMajor != "" && candidateMajor == currentMajor
}

func operationMajor(value string) string {
	matches := operationSchemaPattern.FindStringSubmatch(value)
	if matches == nil {
		return ""
	}
	return matches[1]
}

func failResult(result CaptureResult, code string, message string, path string) (CaptureResult, error) {
	result.Diagnostics = append(result.Diagnostics, report.Diagnostic{
		Severity: "error",
		Code:     code,
		Message:  message,
		Path:     path,
	})
	return result, errors.New(message)
}

func hasErrors(diagnostics []report.Diagnostic) bool {
	for _, diagnostic := range diagnostics {
		if diagnostic.Severity == "error" {
			return true
		}
	}
	return false
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

func splitLines(value string) []string {
	var out []string
	for _, line := range strings.Split(value, "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			out = append(out, line)
		}
	}
	return out
}

func expandHome(path string) string {
	if path == "~" {
		if home, err := os.UserHomeDir(); err == nil {
			return home
		}
	}
	if strings.HasPrefix(path, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			return filepath.Join(home, path[2:])
		}
	}
	return path
}

func resolveOptions(opts CaptureOptions) CaptureOptions {
	if opts.Runner == nil {
		opts.Runner = process.ExecRunner{}
	}
	return opts
}
