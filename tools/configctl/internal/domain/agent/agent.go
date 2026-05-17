package agent

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"configctl/internal/adapters/process"
	"configctl/internal/domain/repo"
	"configctl/internal/report"
)

type Options struct {
	PublicRepoDir   string
	PrivateRepoDir  string
	HomeDir         string
	SkillsetBin     string
	SkillsetProfile string
	SkillsetHome    string
	Runner          process.Runner
	Now             time.Time
}

type StatusResult struct {
	Policy        PolicyStatus        `json:"policy"`
	Skills        SkillsStatus        `json:"skills"`
	SkillsetCheck *SkillsetResult     `json:"skillset_check,omitempty"`
	CodexAuth     CodexAuthStatus     `json:"codex_auth"`
	Diagnostics   []report.Diagnostic `json:"diagnostics"`
}

type PolicyStatus struct {
	Links       []LinkStatus        `json:"links"`
	Diagnostics []report.Diagnostic `json:"diagnostics"`
}

type LinkStatus struct {
	Name           string `json:"name"`
	Path           string `json:"path"`
	Expected       string `json:"expected"`
	Exists         bool   `json:"exists"`
	IsSymlink      bool   `json:"is_symlink"`
	ResolvedTarget string `json:"resolved_target,omitempty"`
	OK             bool   `json:"ok"`
}

type SkillsStatus struct {
	SkillsetBin   string              `json:"skillset_bin"`
	ProfilePath   string              `json:"profile_path"`
	Home          string              `json:"home"`
	ProfileExists bool                `json:"profile_exists"`
	SkillsetFound bool                `json:"skillset_found"`
	Diagnostics   []report.Diagnostic `json:"diagnostics"`
}

type SkillsetResult struct {
	Command             string              `json:"command"`
	Args                []string            `json:"args"`
	ExitCode            int                 `json:"exit_code"`
	Stdout              string              `json:"stdout,omitempty"`
	Stderr              string              `json:"stderr,omitempty"`
	DryRun              bool                `json:"dry_run"`
	OperationReportPath string              `json:"operation_report_path,omitempty"`
	Diagnostics         []report.Diagnostic `json:"diagnostics"`
}

type CodexAuthStatus struct {
	AuthFile    AuthFileStatus      `json:"auth_file"`
	Snapshots   []AuthFileStatus    `json:"snapshots"`
	Diagnostics []report.Diagnostic `json:"diagnostics"`
}

type AuthFileStatus struct {
	Name      string `json:"name"`
	Path      string `json:"path"`
	Exists    bool   `json:"exists"`
	ValidJSON bool   `json:"valid_json"`
	AuthMode  string `json:"auth_mode,omitempty"`
	Mode      string `json:"mode,omitempty"`
	Size      int64  `json:"size,omitempty"`
	Redacted  bool   `json:"redacted"`
}

type AuthMutationResult struct {
	AuthFile            AuthFileStatus      `json:"auth_file"`
	Snapshot            AuthFileStatus      `json:"snapshot"`
	BackupPath          string              `json:"backup_path,omitempty"`
	Changed             bool                `json:"changed"`
	OperationReportPath string              `json:"operation_report_path,omitempty"`
	Diagnostics         []report.Diagnostic `json:"diagnostics"`
}

func Status(opts Options) (StatusResult, error) {
	policy, policyErr := PolicyStatusResult(opts)
	skills := SkillsStatusResult(opts)
	auth := CodexAuthStatusResult(opts)
	result := StatusResult{
		Policy:      policy,
		Skills:      skills,
		CodexAuth:   auth,
		Diagnostics: append(append([]report.Diagnostic{}, policy.Diagnostics...), append(skills.Diagnostics, auth.Diagnostics...)...),
	}
	if policyErr != nil {
		return result, policyErr
	}
	return result, nil
}

func Verify(opts Options) (StatusResult, []report.Diagnostic, error) {
	status, err := Status(opts)
	skillset := Skillset(context.Background(), opts, "verify", false)
	status.SkillsetCheck = &skillset
	status.Diagnostics = append(status.Diagnostics, skillset.Diagnostics...)
	var failures []report.Diagnostic
	for _, diagnostic := range status.Diagnostics {
		if diagnostic.Severity == "error" {
			failures = append(failures, diagnostic)
		}
	}
	return status, failures, err
}

func PolicyStatusResult(opts Options) (PolicyStatus, error) {
	resolved, err := resolveOptions(opts)
	if err != nil {
		return PolicyStatus{}, err
	}
	checks := []struct {
		name     string
		path     string
		expected string
	}{
		{"claude.live", filepath.Join(resolved.HomeDir, ".claude"), filepath.Join(resolved.PrivateRepoDir, ".claude")},
		{"codex.live", filepath.Join(resolved.HomeDir, ".codex"), filepath.Join(resolved.PrivateRepoDir, ".codex")},
		{"claude.policy", filepath.Join(resolved.PrivateRepoDir, ".claude", "CLAUDE.md"), filepath.Join(resolved.PublicRepoDir, ".claude", "CLAUDE.md")},
		{"codex.policy", filepath.Join(resolved.PrivateRepoDir, ".codex", "AGENTS.md"), filepath.Join(resolved.PrivateRepoDir, ".claude", "CLAUDE.md")},
		{"codex.rules", filepath.Join(resolved.PrivateRepoDir, ".codex", "rules"), filepath.Join(resolved.PublicRepoDir, ".codex", "rules")},
	}
	status := PolicyStatus{}
	for _, check := range checks {
		link := inspectLink(check.name, check.path, check.expected)
		status.Links = append(status.Links, link)
		if !link.OK {
			status.Diagnostics = append(status.Diagnostics, report.Diagnostic{
				Severity: "error",
				Code:     "agent.policy.link_invalid",
				Message:  fmt.Sprintf("%s does not point to expected target", check.name),
				Path:     check.path,
			})
		}
	}
	return status, nil
}

func SkillsStatusResult(opts Options) SkillsStatus {
	resolved, err := resolveOptions(opts)
	if err != nil {
		return SkillsStatus{Diagnostics: []report.Diagnostic{{
			Severity: "error",
			Code:     "agent.options_failed",
			Message:  err.Error(),
		}}}
	}
	status := SkillsStatus{
		SkillsetBin: resolved.SkillsetBin,
		ProfilePath: resolved.SkillsetProfile,
		Home:        resolved.SkillsetHome,
	}
	if _, err := os.Stat(resolved.SkillsetProfile); err == nil {
		status.ProfileExists = true
	} else {
		status.Diagnostics = append(status.Diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "agent.skills.profile_missing",
			Message:  err.Error(),
			Path:     resolved.SkillsetProfile,
		})
	}
	if resolved.SkillsetBin != "" {
		if found, err := executableExists(resolved.SkillsetBin); found {
			status.SkillsetFound = true
		} else {
			status.Diagnostics = append(status.Diagnostics, report.Diagnostic{
				Severity: "error",
				Code:     "agent.skills.skillset_missing",
				Message:  err.Error(),
				Path:     resolved.SkillsetBin,
			})
		}
	}
	return status
}

func Skillset(ctx context.Context, opts Options, action string, dryRun bool) SkillsetResult {
	resolved, err := resolveOptions(opts)
	if err != nil {
		return SkillsetResult{Command: action, DryRun: dryRun, ExitCode: -1, Diagnostics: []report.Diagnostic{{
			Severity: "error",
			Code:     "agent.options_failed",
			Message:  err.Error(),
		}}}
	}
	args := []string{"--profile", resolved.SkillsetProfile, "--home", resolved.SkillsetHome, "--repo", resolved.PrivateRepoDir}
	switch action {
	case "list":
		args = append(args, "managed")
	case "verify":
		args = append(args, "check")
	case "sync":
		args = append(args, "apply")
		if !dryRun {
			args = append(args, "--apply")
		}
	default:
		return SkillsetResult{Command: action, DryRun: dryRun, ExitCode: -1, Diagnostics: []report.Diagnostic{{
			Severity: "error",
			Code:     "agent.skills.action_invalid",
			Message:  "unsupported skillset action " + action,
		}}}
	}
	runner := resolved.Runner
	result, err := runner.Run(ctx, process.Invocation{Command: resolved.SkillsetBin, Args: args, Dir: resolved.PrivateRepoDir})
	out := SkillsetResult{
		Command:  action,
		Args:     args,
		ExitCode: result.ExitCode,
		Stdout:   result.Stdout,
		Stderr:   result.Stderr,
		DryRun:   dryRun,
	}
	if err != nil {
		out.Diagnostics = append(out.Diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "agent.skills.run_failed",
			Message:  err.Error(),
		})
		return out
	}
	if result.ExitCode != 0 {
		out.Diagnostics = append(out.Diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "agent.skills.check_failed",
			Message:  fmt.Sprintf("skillset exited %d", result.ExitCode),
		})
	}
	return out
}

func CodexAuthStatusResult(opts Options) CodexAuthStatus {
	resolved, err := resolveOptions(opts)
	if err != nil {
		return CodexAuthStatus{Diagnostics: []report.Diagnostic{{
			Severity: "error",
			Code:     "agent.options_failed",
			Message:  err.Error(),
		}}}
	}
	authDir := filepath.Join(resolved.PrivateRepoDir, ".codex")
	status := CodexAuthStatus{
		AuthFile: inspectAuthFile("auth", filepath.Join(authDir, "auth.json")),
		Snapshots: []AuthFileStatus{
			inspectAuthFile("api", filepath.Join(authDir, "auth.api.json")),
			inspectAuthFile("chatgpt", filepath.Join(authDir, "auth.chatgpt.json")),
		},
	}
	for _, file := range append([]AuthFileStatus{status.AuthFile}, status.Snapshots...) {
		if file.Exists && !file.ValidJSON {
			status.Diagnostics = append(status.Diagnostics, report.Diagnostic{
				Severity: "error",
				Code:     "agent.codex_auth.invalid_json",
				Message:  file.Name + " auth file is not valid JSON",
				Path:     file.Path,
			})
		}
	}
	return status
}

func SaveCodexAuth(opts Options, mode string) (AuthMutationResult, error) {
	resolved, err := resolveOptions(opts)
	if err != nil {
		return AuthMutationResult{}, err
	}
	authPath, snapshotPath, err := authPathsForMode(resolved.PrivateRepoDir, mode)
	if err != nil {
		return AuthMutationResult{}, err
	}
	authStatus := inspectAuthFile("auth", authPath)
	if !authStatus.Exists || !authStatus.ValidJSON {
		return AuthMutationResult{AuthFile: authStatus, Diagnostics: invalidAuthDiagnostics(authStatus)}, errors.New("current Codex auth is invalid")
	}
	if err := copyFileSecure(authPath, snapshotPath, 0o600); err != nil {
		return AuthMutationResult{AuthFile: authStatus, Diagnostics: []report.Diagnostic{{
			Severity: "error",
			Code:     "agent.codex_auth.save_failed",
			Message:  err.Error(),
			Path:     snapshotPath,
		}}}, err
	}
	return AuthMutationResult{
		AuthFile: authStatus,
		Snapshot: inspectAuthFile(mode, snapshotPath),
		Changed:  true,
	}, nil
}

func UseCodexAuth(opts Options, mode string) (AuthMutationResult, error) {
	resolved, err := resolveOptions(opts)
	if err != nil {
		return AuthMutationResult{}, err
	}
	authPath, snapshotPath, err := authPathsForMode(resolved.PrivateRepoDir, mode)
	if err != nil {
		return AuthMutationResult{}, err
	}
	authStatus := inspectAuthFile("auth", authPath)
	snapshotStatus := inspectAuthFile(mode, snapshotPath)
	if !authStatus.Exists || !authStatus.ValidJSON {
		return AuthMutationResult{AuthFile: authStatus, Snapshot: snapshotStatus, Diagnostics: invalidAuthDiagnostics(authStatus)}, errors.New("current Codex auth is invalid")
	}
	if !snapshotStatus.Exists || !snapshotStatus.ValidJSON {
		return AuthMutationResult{AuthFile: authStatus, Snapshot: snapshotStatus, Diagnostics: invalidAuthDiagnostics(snapshotStatus)}, errors.New("Codex auth snapshot is invalid")
	}
	now := resolved.Now
	if now.IsZero() {
		now = time.Now()
	}
	backupPath := authPath + ".bak-" + now.Format("20060102-150405")
	if err := copyFileSecure(authPath, backupPath, 0o600); err != nil {
		return AuthMutationResult{AuthFile: authStatus, Snapshot: snapshotStatus, Diagnostics: []report.Diagnostic{{
			Severity: "error",
			Code:     "agent.codex_auth.backup_failed",
			Message:  err.Error(),
			Path:     backupPath,
		}}}, err
	}
	if err := copyFileSecure(snapshotPath, authPath, 0o600); err != nil {
		return AuthMutationResult{AuthFile: authStatus, Snapshot: snapshotStatus, BackupPath: backupPath, Diagnostics: []report.Diagnostic{{
			Severity: "error",
			Code:     "agent.codex_auth.use_failed",
			Message:  err.Error(),
			Path:     authPath,
		}}}, err
	}
	return AuthMutationResult{
		AuthFile:   inspectAuthFile("auth", authPath),
		Snapshot:   snapshotStatus,
		BackupPath: backupPath,
		Changed:    true,
	}, nil
}

func Summary(status StatusResult) string {
	return fmt.Sprintf("agent status: policy=%d links, skillset=%t, codex_auth=%s",
		len(status.Policy.Links),
		status.Skills.SkillsetFound,
		status.CodexAuth.AuthFile.AuthMode,
	)
}

func resolveOptions(opts Options) (Options, error) {
	resolved := opts
	if resolved.Runner == nil {
		resolved.Runner = process.ExecRunner{}
	}
	if resolved.HomeDir == "" {
		homeDir, err := os.UserHomeDir()
		if err != nil {
			return resolved, err
		}
		resolved.HomeDir = homeDir
	}
	if resolved.PublicRepoDir == "" || resolved.PrivateRepoDir == "" {
		registryPath, err := repo.DefaultRegistryPath()
		if err == nil {
			registry, _, err := repo.LoadRegistry(registryPath)
			if err == nil {
				for _, definition := range registry.Repos {
					switch definition.Name {
					case "public-dotfiles":
						if resolved.PublicRepoDir == "" {
							resolved.PublicRepoDir = definition.Path
						}
					case "private-config":
						if resolved.PrivateRepoDir == "" {
							resolved.PrivateRepoDir = definition.Path
						}
					}
				}
			}
		}
	}
	if resolved.PrivateRepoDir == "" && resolved.PublicRepoDir != "" {
		resolved.PrivateRepoDir = filepath.Join(filepath.Dir(resolved.PublicRepoDir), "private-config")
	}
	if resolved.PublicRepoDir == "" || resolved.PrivateRepoDir == "" {
		return resolved, errors.New("could not resolve public/private repo paths")
	}
	resolved.PublicRepoDir = cleanAbs(resolved.PublicRepoDir)
	resolved.PrivateRepoDir = cleanAbs(resolved.PrivateRepoDir)
	if resolved.SkillsetProfile == "" {
		resolved.SkillsetProfile = filepath.Join(resolved.PrivateRepoDir, "skills.profile.yaml")
	}
	if resolved.SkillsetHome == "" {
		resolved.SkillsetHome = resolved.HomeDir
	}
	if resolved.SkillsetBin == "" {
		resolved.SkillsetBin = resolveSkillsetBin(resolved.PrivateRepoDir)
	}
	return resolved, nil
}

func resolveSkillsetBin(privateRepo string) string {
	if value := os.Getenv("SKILLSET_BIN"); value != "" {
		return value
	}
	local := filepath.Join(filepath.Dir(privateRepo), "github", "gh-xj", "skillset", "bin", "skillset")
	if info, err := os.Stat(local); err == nil && !info.IsDir() && info.Mode()&0o111 != 0 {
		return local
	}
	return "skillset"
}

func executableExists(command string) (bool, error) {
	if strings.ContainsRune(command, filepath.Separator) {
		info, err := os.Stat(command)
		if err != nil {
			return false, err
		}
		if info.IsDir() {
			return false, fmt.Errorf("%s is a directory", command)
		}
		if info.Mode()&0o111 == 0 {
			return false, fmt.Errorf("%s is not executable", command)
		}
		return true, nil
	}
	_, err := exec.LookPath(command)
	if err != nil {
		return false, err
	}
	return true, nil
}

func inspectLink(name string, path string, expected string) LinkStatus {
	resolved, exists, isSymlink := resolveLive(path)
	return LinkStatus{
		Name:           name,
		Path:           path,
		Expected:       expected,
		Exists:         exists,
		IsSymlink:      isSymlink,
		ResolvedTarget: resolved,
		OK:             exists && isSymlink && samePath(resolved, expected),
	}
}

func inspectAuthFile(name string, path string) AuthFileStatus {
	status := AuthFileStatus{Name: name, Path: path, Redacted: true}
	info, err := os.Stat(path)
	if err != nil {
		return status
	}
	status.Exists = true
	status.Mode = fmt.Sprintf("%04o", info.Mode().Perm())
	status.Size = info.Size()
	var values map[string]any
	data, err := os.ReadFile(path)
	if err != nil {
		return status
	}
	if err := json.Unmarshal(data, &values); err != nil {
		return status
	}
	status.ValidJSON = true
	if mode, ok := values["auth_mode"].(string); ok && mode != "" {
		status.AuthMode = mode
	} else {
		status.AuthMode = "api-key"
	}
	return status
}

func authPathsForMode(privateRepo string, mode string) (string, string, error) {
	authDir := filepath.Join(privateRepo, ".codex")
	switch mode {
	case "api":
		return filepath.Join(authDir, "auth.json"), filepath.Join(authDir, "auth.api.json"), nil
	case "chatgpt":
		return filepath.Join(authDir, "auth.json"), filepath.Join(authDir, "auth.chatgpt.json"), nil
	default:
		return "", "", fmt.Errorf("unsupported Codex auth mode %q", mode)
	}
}

func invalidAuthDiagnostics(status AuthFileStatus) []report.Diagnostic {
	code := "agent.codex_auth.invalid_json"
	message := status.Name + " auth file is not valid JSON"
	if !status.Exists {
		code = "agent.codex_auth.missing"
		message = status.Name + " auth file is missing"
	}
	return []report.Diagnostic{{
		Severity: "error",
		Code:     code,
		Message:  message,
		Path:     status.Path,
	}}
}

func copyFileSecure(source string, destination string, perm os.FileMode) error {
	data, err := os.ReadFile(source)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(destination), 0o755); err != nil {
		return err
	}
	return writeFileSecure(destination, data, perm)
}

func writeFileSecure(path string, data []byte, perm os.FileMode) error {
	dir := filepath.Dir(path)
	temp, err := os.CreateTemp(dir, "."+filepath.Base(path)+".tmp-*")
	if err != nil {
		return err
	}
	tempPath := temp.Name()
	cleanup := true
	defer func() {
		if cleanup {
			_ = os.Remove(tempPath)
		}
	}()
	if err := temp.Chmod(perm); err != nil {
		_ = temp.Close()
		return err
	}
	if _, err := temp.Write(data); err != nil {
		_ = temp.Close()
		return err
	}
	if err := temp.Close(); err != nil {
		return err
	}
	if err := os.Rename(tempPath, path); err != nil {
		return err
	}
	cleanup = false
	return os.Chmod(path, perm)
}

func resolveLive(path string) (string, bool, bool) {
	info, err := os.Lstat(path)
	if err != nil {
		return "", false, false
	}
	isSymlink := info.Mode()&os.ModeSymlink != 0
	if evaluated, err := filepath.EvalSymlinks(path); err == nil {
		return filepath.Clean(evaluated), true, isSymlink
	}
	if !isSymlink {
		return filepath.Clean(path), true, false
	}
	target, err := os.Readlink(path)
	if err != nil {
		return "", true, true
	}
	if !filepath.IsAbs(target) {
		target = filepath.Join(filepath.Dir(path), target)
	}
	return filepath.Clean(target), true, true
}

func samePath(a string, b string) bool {
	if a == "" || b == "" {
		return false
	}
	if evaluated, err := filepath.EvalSymlinks(a); err == nil {
		a = evaluated
	}
	if evaluated, err := filepath.EvalSymlinks(b); err == nil {
		b = evaluated
	}
	return filepath.Clean(a) == filepath.Clean(b)
}

func cleanAbs(path string) string {
	abs, err := filepath.Abs(path)
	if err != nil {
		return filepath.Clean(path)
	}
	return abs
}
