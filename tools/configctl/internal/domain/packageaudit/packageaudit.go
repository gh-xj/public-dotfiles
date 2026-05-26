package packageaudit

import (
	"context"
	"encoding/json"
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

type Options struct {
	PublicRepoDir  string
	PrivateRepoDir string
	Runner         process.Runner
}

type StatusResult struct {
	Ledgers     []LedgerStatus      `json:"ledgers"`
	Installed   InstalledStatus     `json:"installed"`
	Audit       AuditResult         `json:"audit"`
	Diagnostics []report.Diagnostic `json:"diagnostics"`
}

type LedgerStatus struct {
	Repo        string              `json:"repo"`
	Path        string              `json:"path"`
	Exists      bool                `json:"exists"`
	Brew        BrewLedger          `json:"brew"`
	NPM         NPMLedger           `json:"npm"`
	Diagnostics []report.Diagnostic `json:"diagnostics"`
}

type BrewLedger struct {
	Taps     []PackageRef   `json:"taps"`
	Formulae []PackageRef   `json:"formulae"`
	Casks    []PackageRef   `json:"casks"`
	Counts   map[string]int `json:"counts"`
}

type NPMLedger struct {
	Packages []PackageRef   `json:"packages"`
	Counts   map[string]int `json:"counts"`
}

type PackageRef struct {
	Manager string `json:"manager"`
	Kind    string `json:"kind"`
	Name    string `json:"name"`
	Repo    string `json:"repo"`
	Path    string `json:"path"`
	Line    int    `json:"line"`
}

type InstalledStatus struct {
	Brew        BrewInstalled       `json:"brew"`
	NPM         NPMInstalled        `json:"npm"`
	Diagnostics []report.Diagnostic `json:"diagnostics"`
}

type BrewInstalled struct {
	Available         bool     `json:"available"`
	Formulae          []string `json:"formulae"`
	RequestedFormulae []string `json:"requested_formulae"`
	Casks             []string `json:"casks"`
}

type NPMInstalled struct {
	Available bool     `json:"available"`
	Packages  []string `json:"packages"`
}

type AuditResult struct {
	TrackedMissing             []Finding           `json:"tracked_missing"`
	InstalledUntracked         []Finding           `json:"installed_untracked"`
	Duplicated                 []Finding           `json:"duplicated"`
	ConfigWithoutLedgerSupport []Finding           `json:"config_without_package_ledger_support"`
	Counts                     map[string]int      `json:"counts"`
	Diagnostics                []report.Diagnostic `json:"diagnostics"`
}

type Finding struct {
	Manager string   `json:"manager"`
	Kind    string   `json:"kind"`
	Name    string   `json:"name"`
	Repos   []string `json:"repos,omitempty"`
	Paths   []string `json:"paths,omitempty"`
	Message string   `json:"message"`
}

type ConfigSupport struct {
	Path    string
	Manager string
	Kind    string
	Name    string
}

var brewLinePattern = regexp.MustCompile(`^\s*(tap|brew|cask)\s+"([^"]+)"`)

var configSupport = []ConfigSupport{
	{Path: ".claude/settings.json", Manager: "npm", Kind: "global", Name: "@anthropic-ai/claude-code"},
	{Path: ".codex/config.toml", Manager: "npm", Kind: "global", Name: "@openai/codex"},
	{Path: ".config/amethyst/amethyst.yml", Manager: "brew", Kind: "cask", Name: "amethyst"},
	{Path: ".config/bat/config", Manager: "brew", Kind: "formula", Name: "bat"},
	{Path: "modules/home/terminal.nix", Manager: "brew", Kind: "cask", Name: "ghostty"},
	{Path: ".config/karabiner/karabiner.json", Manager: "brew", Kind: "cask", Name: "karabiner-elements"},
	{Path: ".config/lazydocker/config.yml", Manager: "brew", Kind: "formula", Name: "lazydocker"},
	{Path: ".config/lazygit/config.yml", Manager: "brew", Kind: "formula", Name: "lazygit"},
	{Path: ".config/nvim/init.lua", Manager: "brew", Kind: "formula", Name: "neovim"},
	{Path: ".config/starship.toml", Manager: "brew", Kind: "formula", Name: "starship"},
	{Path: ".config/yazi/yazi.toml", Manager: "brew", Kind: "formula", Name: "yazi"},
	{Path: ".tmux.conf", Manager: "brew", Kind: "formula", Name: "tmux"},
	{Path: ".zshrc", Manager: "brew", Kind: "formula", Name: "zsh"},
	{Path: "Library/Application Support/TypeWhisper/lexicon.json", Manager: "brew", Kind: "cask", Name: "typewhisper"},
}

func Status(ctx context.Context, opts Options) StatusResult {
	resolved := resolveOptions(opts)
	status := StatusResult{}
	status.Ledgers = loadLedgers(resolved)
	status.Installed = inspectInstalled(ctx, resolved)
	status.Audit = audit(resolved, status.Ledgers, status.Installed)
	status.Diagnostics = collectDiagnostics(status.Ledgers, status.Installed, status.Audit)
	return status
}

func Verify(ctx context.Context, opts Options) (StatusResult, []report.Diagnostic) {
	status := Status(ctx, opts)
	var failures []report.Diagnostic
	for _, diagnostic := range status.Diagnostics {
		if diagnostic.Severity == "error" {
			failures = append(failures, diagnostic)
		}
	}
	return status, failures
}

func Summary(status StatusResult) string {
	brewTracked := 0
	npmTracked := 0
	for _, ledger := range status.Ledgers {
		brewTracked += len(ledger.Brew.Formulae) + len(ledger.Brew.Casks)
		npmTracked += len(ledger.NPM.Packages)
	}
	findings := status.Audit.Counts["tracked_missing"] +
		status.Audit.Counts["installed_untracked"] +
		status.Audit.Counts["duplicated"] +
		status.Audit.Counts["config_without_package_ledger_support"]
	return fmt.Sprintf("package status: %d brew entries, %d npm globals, %d audit finding(s)", brewTracked, npmTracked, findings)
}

func AuditSummary(audit AuditResult) string {
	findings := audit.Counts["tracked_missing"] +
		audit.Counts["installed_untracked"] +
		audit.Counts["duplicated"] +
		audit.Counts["config_without_package_ledger_support"]
	return fmt.Sprintf("package audit: %d finding(s)", findings)
}

func VerifySummary(failures []report.Diagnostic) string {
	if len(failures) == 0 {
		return "package verify: package ledgers inspected"
	}
	return fmt.Sprintf("package verify failed: %d inspection error(s)", len(failures))
}

func loadLedgers(opts Options) []LedgerStatus {
	repos := []struct {
		name string
		path string
	}{
		{name: "public-dotfiles", path: opts.PublicRepoDir},
		{name: "private-config", path: opts.PrivateRepoDir},
	}
	var ledgers []LedgerStatus
	for _, repoDef := range repos {
		if repoDef.path == "" {
			continue
		}
		ledger := LedgerStatus{
			Repo: repoDef.name,
			Path: repoDef.path,
		}
		if info, err := os.Stat(repoDef.path); err != nil {
			ledger.Diagnostics = append(ledger.Diagnostics, report.Diagnostic{
				Severity: "warning",
				Code:     "package.repo_missing",
				Message:  err.Error(),
				Path:     repoDef.path,
			})
			ledgers = append(ledgers, ledger)
			continue
		} else if !info.IsDir() {
			ledger.Diagnostics = append(ledger.Diagnostics, report.Diagnostic{
				Severity: "error",
				Code:     "package.repo_not_directory",
				Message:  "package repo path is not a directory",
				Path:     repoDef.path,
			})
			ledgers = append(ledgers, ledger)
			continue
		}
		ledger.Exists = true
		ledger.Brew, ledger.Diagnostics = parseBrewfile(filepath.Join(repoDef.path, "Brewfile"), repoDef.name, ledger.Diagnostics)
		ledger.NPM, ledger.Diagnostics = parseNPMGlobals(filepath.Join(repoDef.path, "npm-globals.txt"), repoDef.name, ledger.Diagnostics)
		ledgers = append(ledgers, ledger)
	}
	return ledgers
}

func parseBrewfile(path string, repoName string, diagnostics []report.Diagnostic) (BrewLedger, []report.Diagnostic) {
	ledger := BrewLedger{Counts: map[string]int{}}
	data, err := os.ReadFile(path)
	if err != nil {
		severity := "warning"
		if !os.IsNotExist(err) {
			severity = "error"
		}
		diagnostics = append(diagnostics, report.Diagnostic{
			Severity: severity,
			Code:     "package.brewfile_read_failed",
			Message:  err.Error(),
			Path:     path,
		})
		return ledger, diagnostics
	}
	lines := strings.Split(string(data), "\n")
	for i, line := range lines {
		matches := brewLinePattern.FindStringSubmatch(line)
		if matches == nil {
			continue
		}
		kind := matches[1]
		name := matches[2]
		ref := PackageRef{Manager: "brew", Kind: kind, Name: name, Repo: repoName, Path: path, Line: i + 1}
		switch kind {
		case "tap":
			ledger.Taps = append(ledger.Taps, ref)
		case "brew":
			ref.Kind = "formula"
			ledger.Formulae = append(ledger.Formulae, ref)
		case "cask":
			ledger.Casks = append(ledger.Casks, ref)
		}
	}
	sortRefs(ledger.Taps)
	sortRefs(ledger.Formulae)
	sortRefs(ledger.Casks)
	ledger.Counts["tap"] = len(ledger.Taps)
	ledger.Counts["formula"] = len(ledger.Formulae)
	ledger.Counts["cask"] = len(ledger.Casks)
	return ledger, diagnostics
}

func parseNPMGlobals(path string, repoName string, diagnostics []report.Diagnostic) (NPMLedger, []report.Diagnostic) {
	ledger := NPMLedger{Counts: map[string]int{}}
	data, err := os.ReadFile(path)
	if err != nil {
		severity := "warning"
		if !os.IsNotExist(err) {
			severity = "error"
		}
		diagnostics = append(diagnostics, report.Diagnostic{
			Severity: severity,
			Code:     "package.npm_globals_read_failed",
			Message:  err.Error(),
			Path:     path,
		})
		return ledger, diagnostics
	}
	for i, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		ledger.Packages = append(ledger.Packages, PackageRef{
			Manager: "npm",
			Kind:    "global",
			Name:    line,
			Repo:    repoName,
			Path:    path,
			Line:    i + 1,
		})
	}
	sortRefs(ledger.Packages)
	ledger.Counts["global"] = len(ledger.Packages)
	return ledger, diagnostics
}

func inspectInstalled(ctx context.Context, opts Options) InstalledStatus {
	runner := opts.Runner
	status := InstalledStatus{}
	status.Brew = inspectBrew(ctx, runner, &status.Diagnostics)
	status.NPM = inspectNPM(ctx, runner, &status.Diagnostics)
	return status
}

func inspectBrew(ctx context.Context, runner process.Runner, diagnostics *[]report.Diagnostic) BrewInstalled {
	if !commandAvailable(ctx, runner, "brew") {
		*diagnostics = append(*diagnostics, report.Diagnostic{
			Severity: "warning",
			Code:     "package.brew_unavailable",
			Message:  "brew is not available",
		})
		return BrewInstalled{}
	}
	installed := BrewInstalled{Available: true}
	installed.Formulae = runLines(ctx, runner, diagnostics, "brew", []string{"list", "--formula", "-1"})
	installed.RequestedFormulae = runLines(ctx, runner, diagnostics, "brew", []string{"leaves", "--installed-on-request"})
	if len(installed.RequestedFormulae) == 0 {
		installed.RequestedFormulae = runLines(ctx, runner, diagnostics, "brew", []string{"leaves", "-r"})
	}
	installed.Casks = runLines(ctx, runner, diagnostics, "brew", []string{"list", "--cask", "-1"})
	sort.Strings(installed.Formulae)
	sort.Strings(installed.RequestedFormulae)
	sort.Strings(installed.Casks)
	return installed
}

func inspectNPM(ctx context.Context, runner process.Runner, diagnostics *[]report.Diagnostic) NPMInstalled {
	if !commandAvailable(ctx, runner, "npm") {
		*diagnostics = append(*diagnostics, report.Diagnostic{
			Severity: "warning",
			Code:     "package.npm_unavailable",
			Message:  "npm is not available",
		})
		return NPMInstalled{}
	}
	result, err := runner.Run(ctx, process.Invocation{Command: "npm", Args: []string{"ls", "-g", "--depth=0", "--json"}})
	if err != nil {
		*diagnostics = append(*diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "package.npm_list_failed",
			Message:  err.Error(),
		})
		return NPMInstalled{Available: true}
	}
	var parsed struct {
		Dependencies map[string]json.RawMessage `json:"dependencies"`
	}
	if jsonErr := json.Unmarshal([]byte(result.Stdout), &parsed); jsonErr != nil {
		*diagnostics = append(*diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "package.npm_list_parse_failed",
			Message:  jsonErr.Error(),
		})
		return NPMInstalled{Available: true}
	}
	installed := NPMInstalled{Available: true}
	for name := range parsed.Dependencies {
		installed.Packages = append(installed.Packages, name)
	}
	sort.Strings(installed.Packages)
	if result.ExitCode != 0 {
		*diagnostics = append(*diagnostics, report.Diagnostic{
			Severity: "warning",
			Code:     "package.npm_list_nonzero",
			Message:  fmt.Sprintf("npm ls exited %d after producing package data", result.ExitCode),
		})
	}
	return installed
}

func runLines(ctx context.Context, runner process.Runner, diagnostics *[]report.Diagnostic, command string, args []string) []string {
	result, err := runner.Run(ctx, process.Invocation{Command: command, Args: args})
	if err != nil {
		*diagnostics = append(*diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "package.command_failed",
			Message:  err.Error(),
		})
		return nil
	}
	if result.ExitCode != 0 {
		message := strings.TrimSpace(result.Stderr)
		if message == "" {
			message = strings.TrimSpace(result.Stdout)
		}
		*diagnostics = append(*diagnostics, report.Diagnostic{
			Severity: "warning",
			Code:     "package.command_nonzero",
			Message:  fmt.Sprintf("%s %s exited %d: %s", command, strings.Join(args, " "), result.ExitCode, message),
		})
	}
	return splitLines(result.Stdout)
}

func commandAvailable(ctx context.Context, runner process.Runner, command string) bool {
	result, err := runner.Run(ctx, process.Invocation{Command: "sh", Args: []string{"-c", "command -v " + shellQuote(command) + " >/dev/null 2>&1"}})
	return err == nil && result.ExitCode == 0
}

func audit(opts Options, ledgers []LedgerStatus, installed InstalledStatus) AuditResult {
	audit := AuditResult{Counts: map[string]int{}}
	allRefs := refsByKey(ledgers)
	audit.TrackedMissing = trackedMissing(allRefs, installed)
	audit.InstalledUntracked = installedUntracked(allRefs, installed)
	audit.Duplicated = duplicatedRefs(allRefs)
	audit.ConfigWithoutLedgerSupport = configWithoutLedgerSupport(opts, allRefs)
	sortFindings(audit.TrackedMissing)
	sortFindings(audit.InstalledUntracked)
	sortFindings(audit.Duplicated)
	sortFindings(audit.ConfigWithoutLedgerSupport)
	audit.Counts["tracked_missing"] = len(audit.TrackedMissing)
	audit.Counts["installed_untracked"] = len(audit.InstalledUntracked)
	audit.Counts["duplicated"] = len(audit.Duplicated)
	audit.Counts["config_without_package_ledger_support"] = len(audit.ConfigWithoutLedgerSupport)
	audit.Diagnostics = auditDiagnostics(audit)
	return audit
}

func refsByKey(ledgers []LedgerStatus) map[string][]PackageRef {
	refs := map[string][]PackageRef{}
	for _, ledger := range ledgers {
		for _, ref := range ledger.Brew.Formulae {
			refs[key(ref.Manager, ref.Kind, ref.Name)] = append(refs[key(ref.Manager, ref.Kind, ref.Name)], ref)
		}
		for _, ref := range ledger.Brew.Casks {
			refs[key(ref.Manager, ref.Kind, ref.Name)] = append(refs[key(ref.Manager, ref.Kind, ref.Name)], ref)
		}
		for _, ref := range ledger.NPM.Packages {
			refs[key(ref.Manager, ref.Kind, ref.Name)] = append(refs[key(ref.Manager, ref.Kind, ref.Name)], ref)
		}
	}
	return refs
}

func trackedMissing(refs map[string][]PackageRef, installed InstalledStatus) []Finding {
	var findings []Finding
	formulae := toSet(append(append([]string{}, installed.Brew.Formulae...), installed.Brew.RequestedFormulae...))
	casks := toSet(installed.Brew.Casks)
	npmPackages := toSet(installed.NPM.Packages)
	for _, items := range refs {
		ref := items[0]
		switch {
		case ref.Manager == "brew" && ref.Kind == "formula" && installed.Brew.Available && !formulaNameInSet(ref.Name, formulae):
			findings = append(findings, findingFromRefs(ref, items, "tracked brew formula is not installed"))
		case ref.Manager == "brew" && ref.Kind == "cask" && installed.Brew.Available && !casks[ref.Name]:
			findings = append(findings, findingFromRefs(ref, items, "tracked brew cask is not installed"))
		case ref.Manager == "npm" && installed.NPM.Available && !npmPackages[ref.Name]:
			findings = append(findings, findingFromRefs(ref, items, "tracked npm global package is not installed"))
		}
	}
	return findings
}

func installedUntracked(refs map[string][]PackageRef, installed InstalledStatus) []Finding {
	var findings []Finding
	if installed.Brew.Available {
		for _, name := range installed.Brew.RequestedFormulae {
			if !formulaRefExists(refs, name) {
				findings = append(findings, Finding{Manager: "brew", Kind: "formula", Name: name, Message: "installed requested brew formula is not tracked"})
			}
		}
		for _, name := range installed.Brew.Casks {
			if _, ok := refs[key("brew", "cask", name)]; !ok {
				findings = append(findings, Finding{Manager: "brew", Kind: "cask", Name: name, Message: "installed brew cask is not tracked"})
			}
		}
	}
	if installed.NPM.Available {
		for _, name := range installed.NPM.Packages {
			if _, ok := refs[key("npm", "global", name)]; !ok {
				findings = append(findings, Finding{Manager: "npm", Kind: "global", Name: name, Message: "installed npm global package is not tracked"})
			}
		}
	}
	return findings
}

func duplicatedRefs(refs map[string][]PackageRef) []Finding {
	var findings []Finding
	for _, items := range refs {
		if len(items) < 2 {
			continue
		}
		ref := items[0]
		findings = append(findings, findingFromRefs(ref, items, "package is tracked in multiple ledger entries"))
	}
	return findings
}

func configWithoutLedgerSupport(opts Options, refs map[string][]PackageRef) []Finding {
	var findings []Finding
	for _, support := range configSupport {
		if _, ok := refs[key(support.Manager, support.Kind, support.Name)]; ok {
			continue
		}
		var paths []string
		for _, root := range []string{opts.PublicRepoDir, opts.PrivateRepoDir} {
			if root == "" {
				continue
			}
			path := filepath.Join(root, support.Path)
			if _, err := os.Stat(path); err == nil {
				paths = append(paths, path)
			}
		}
		if len(paths) > 0 {
			findings = append(findings, Finding{
				Manager: support.Manager,
				Kind:    support.Kind,
				Name:    support.Name,
				Paths:   paths,
				Message: "config exists without package ledger support",
			})
		}
	}
	return findings
}

func auditDiagnostics(audit AuditResult) []report.Diagnostic {
	var diagnostics []report.Diagnostic
	for _, finding := range audit.TrackedMissing {
		diagnostics = append(diagnostics, diagnosticFromFinding("warning", "package.tracked_missing", finding))
	}
	for _, finding := range audit.InstalledUntracked {
		diagnostics = append(diagnostics, diagnosticFromFinding("warning", "package.installed_untracked", finding))
	}
	for _, finding := range audit.Duplicated {
		diagnostics = append(diagnostics, diagnosticFromFinding("warning", "package.duplicated", finding))
	}
	for _, finding := range audit.ConfigWithoutLedgerSupport {
		diagnostics = append(diagnostics, diagnosticFromFinding("warning", "package.config_without_ledger", finding))
	}
	return diagnostics
}

func diagnosticFromFinding(severity string, code string, finding Finding) report.Diagnostic {
	message := fmt.Sprintf("%s %s %s: %s", finding.Manager, finding.Kind, finding.Name, finding.Message)
	path := ""
	if len(finding.Paths) > 0 {
		path = finding.Paths[0]
	}
	return report.Diagnostic{Severity: severity, Code: code, Message: message, Path: path}
}

func findingFromRefs(ref PackageRef, refs []PackageRef, message string) Finding {
	finding := Finding{
		Manager: ref.Manager,
		Kind:    ref.Kind,
		Name:    ref.Name,
		Message: message,
	}
	for _, item := range refs {
		finding.Repos = append(finding.Repos, item.Repo)
		finding.Paths = append(finding.Paths, fmt.Sprintf("%s:%d", item.Path, item.Line))
	}
	finding.Repos = uniqueStrings(finding.Repos)
	sort.Strings(finding.Paths)
	return finding
}

func collectDiagnostics(ledgers []LedgerStatus, installed InstalledStatus, audit AuditResult) []report.Diagnostic {
	var diagnostics []report.Diagnostic
	for _, ledger := range ledgers {
		diagnostics = append(diagnostics, ledger.Diagnostics...)
	}
	diagnostics = append(diagnostics, installed.Diagnostics...)
	diagnostics = append(diagnostics, audit.Diagnostics...)
	return diagnostics
}

func resolveOptions(opts Options) Options {
	if opts.Runner == nil {
		opts.Runner = process.ExecRunner{}
	}
	if opts.PublicRepoDir == "" || opts.PrivateRepoDir == "" {
		if registryPath, err := repo.DefaultRegistryPath(); err == nil {
			registry, _, loadErr := repo.LoadRegistry(registryPath)
			if loadErr == nil {
				for _, definition := range registry.Repos {
					switch definition.Name {
					case "public-dotfiles":
						if opts.PublicRepoDir == "" {
							opts.PublicRepoDir = definition.Path
						}
					case "private-config":
						if opts.PrivateRepoDir == "" {
							opts.PrivateRepoDir = definition.Path
						}
					}
				}
			}
			if opts.PublicRepoDir == "" {
				opts.PublicRepoDir = repo.PublicRootFromRegistry(registryPath)
			}
		}
	}
	return opts
}

func key(manager string, kind string, name string) string {
	return manager + "\x00" + kind + "\x00" + name
}

func toSet(values []string) map[string]bool {
	set := map[string]bool{}
	for _, value := range values {
		set[value] = true
	}
	return set
}

func formulaRefExists(refs map[string][]PackageRef, name string) bool {
	if _, ok := refs[key("brew", "formula", name)]; ok {
		return true
	}
	base := formulaBaseName(name)
	for _, items := range refs {
		if len(items) == 0 {
			continue
		}
		ref := items[0]
		if ref.Manager == "brew" && ref.Kind == "formula" && formulaBaseName(ref.Name) == base {
			return true
		}
	}
	return false
}

func formulaNameInSet(name string, set map[string]bool) bool {
	if set[name] {
		return true
	}
	base := formulaBaseName(name)
	for installed := range set {
		if formulaBaseName(installed) == base {
			return true
		}
	}
	return false
}

func formulaBaseName(name string) string {
	parts := strings.Split(name, "/")
	if len(parts) == 0 {
		return name
	}
	return parts[len(parts)-1]
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

func sortRefs(refs []PackageRef) {
	sort.Slice(refs, func(i, j int) bool {
		if refs[i].Name != refs[j].Name {
			return refs[i].Name < refs[j].Name
		}
		if refs[i].Path != refs[j].Path {
			return refs[i].Path < refs[j].Path
		}
		return refs[i].Line < refs[j].Line
	})
}

func sortFindings(findings []Finding) {
	sort.Slice(findings, func(i, j int) bool {
		if findings[i].Manager != findings[j].Manager {
			return findings[i].Manager < findings[j].Manager
		}
		if findings[i].Kind != findings[j].Kind {
			return findings[i].Kind < findings[j].Kind
		}
		return findings[i].Name < findings[j].Name
	})
}

func uniqueStrings(values []string) []string {
	seen := map[string]struct{}{}
	var out []string
	for _, value := range values {
		if _, ok := seen[value]; ok {
			continue
		}
		seen[value] = struct{}{}
		out = append(out, value)
	}
	sort.Strings(out)
	return out
}

func shellQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'"
}
