package home

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"configctl/internal/report"
)

type Options struct {
	HomeDir        string
	PublicRepoDir  string
	PrivateRepoDir string
	PublicOnly     bool
	ModeOverride   Mode
	VerifyAll      bool
}

type Topology struct {
	HomeDir     string              `json:"home_dir"`
	PublicRepo  string              `json:"public_repo,omitempty"`
	PrivateRepo string              `json:"private_repo,omitempty"`
	Manifests   []LoadedManifest    `json:"manifests"`
	Entries     []ResolvedEntry     `json:"entries"`
	Diagnostics []report.Diagnostic `json:"diagnostics"`
}

type ResolvedEntry struct {
	Owner        string `json:"owner"`
	Path         string `json:"path"`
	Mode         Mode   `json:"mode"`
	Strategy     string `json:"strategy,omitempty"`
	SourcePath   string `json:"source_path"`
	TargetPath   string `json:"target_path"`
	ManifestPath string `json:"manifest_path"`
}

type EntryState struct {
	Owner          string `json:"owner"`
	Path           string `json:"path"`
	Mode           Mode   `json:"mode"`
	Strategy       string `json:"strategy,omitempty"`
	SourcePath     string `json:"source_path"`
	TargetPath     string `json:"target_path"`
	Exists         bool   `json:"exists"`
	IsSymlink      bool   `json:"is_symlink"`
	ResolvedTarget string `json:"resolved_target,omitempty"`
	Status         string `json:"status"`
	Action         string `json:"action"`
}

type StatusResult struct {
	HomeDir     string              `json:"home_dir"`
	Entries     []EntryState        `json:"entries"`
	Counts      map[string]int      `json:"counts"`
	Diagnostics []report.Diagnostic `json:"diagnostics"`
}

type ResolveResult struct {
	Input          string              `json:"input"`
	TargetPath     string              `json:"target_path"`
	Exists         bool                `json:"exists"`
	IsSymlink      bool                `json:"is_symlink"`
	ResolvedTarget string              `json:"resolved_target,omitempty"`
	Entry          *ResolvedEntry      `json:"entry,omitempty"`
	Owner          string              `json:"owner,omitempty"`
	Diagnostics    []report.Diagnostic `json:"diagnostics"`
}

func Load(opts Options) (Topology, error) {
	homeDir, err := resolveHome(opts.HomeDir)
	if err != nil {
		return Topology{}, err
	}
	publicRepo, privateRepo, err := resolveRepos(opts.PublicRepoDir, opts.PrivateRepoDir)
	if err != nil {
		return Topology{}, err
	}
	topology := Topology{
		HomeDir:     homeDir,
		PublicRepo:  publicRepo,
		PrivateRepo: privateRepo,
	}
	if publicRepo != "" && ManifestExists(publicRepo) {
		loaded, diagnostics, err := LoadManifest("public", publicRepo)
		topology.Diagnostics = append(topology.Diagnostics, diagnostics...)
		if err != nil {
			return topology, err
		}
		topology.Manifests = append(topology.Manifests, loaded)
		topology.Entries = append(topology.Entries, resolveEntries(homeDir, loaded)...)
	} else if publicRepo != "" {
		topology.Diagnostics = append(topology.Diagnostics, report.Diagnostic{
			Severity: "warning",
			Code:     "home.manifest_missing",
			Message:  "public home manifest missing",
			Path:     filepath.Join(publicRepo, manifestRelPath),
		})
	}
	if !opts.PublicOnly && privateRepo != "" && ManifestExists(privateRepo) {
		loaded, diagnostics, err := LoadManifest("private", privateRepo)
		topology.Diagnostics = append(topology.Diagnostics, diagnostics...)
		if err != nil {
			return topology, err
		}
		topology.Manifests = append(topology.Manifests, loaded)
		topology.Entries = append(topology.Entries, resolveEntries(homeDir, loaded)...)
	} else if !opts.PublicOnly && privateRepo != "" {
		topology.Diagnostics = append(topology.Diagnostics, report.Diagnostic{
			Severity: "warning",
			Code:     "home.manifest_missing",
			Message:  "private home manifest missing",
			Path:     filepath.Join(privateRepo, manifestRelPath),
		})
	}
	sort.Slice(topology.Entries, func(i, j int) bool {
		if topology.Entries[i].Path == topology.Entries[j].Path {
			return topology.Entries[i].Owner < topology.Entries[j].Owner
		}
		return topology.Entries[i].Path < topology.Entries[j].Path
	})
	return topology, nil
}

func Status(opts Options) (StatusResult, error) {
	topology, err := Load(opts)
	if err != nil {
		return StatusResult{}, err
	}
	return inspectTopology(topology, opts, nil), nil
}

func inspectTopology(topology Topology, opts Options, include func(ResolvedEntry) bool) StatusResult {
	result := StatusResult{
		HomeDir:     topology.HomeDir,
		Counts:      map[string]int{},
		Diagnostics: append([]report.Diagnostic{}, topology.Diagnostics...),
	}
	for _, entry := range topology.Entries {
		if include != nil && !include(entry) {
			continue
		}
		state := InspectEntry(entry, opts.ModeOverride)
		result.Entries = append(result.Entries, state)
		result.Counts[state.Status]++
		if state.Status == "source_missing" {
			result.Diagnostics = append(result.Diagnostics, report.Diagnostic{
				Severity: "warning",
				Code:     "home.source_missing",
				Message:  "manifest source path is missing",
				Path:     state.SourcePath,
			})
		}
	}
	return result
}

func Verify(opts Options) (StatusResult, []report.Diagnostic, error) {
	topology, err := Load(opts)
	if err != nil {
		return StatusResult{}, nil, err
	}
	include := representativeVerifyEntry
	if opts.VerifyAll {
		include = nil
	}
	result := inspectTopology(topology, opts, include)
	var failures []report.Diagnostic
	for _, state := range result.Entries {
		switch state.Mode {
		case ModeLink:
			if state.Status != "linked" {
				failures = append(failures, report.Diagnostic{
					Severity: "error",
					Code:     "home.verify.link_not_owned",
					Message:  fmt.Sprintf("%s should link to %s", state.TargetPath, state.SourcePath),
					Path:     state.TargetPath,
				})
			}
		case ModeCopy, ModeMerge:
			if state.Status == "missing" || state.Status == "source_missing" {
				failures = append(failures, report.Diagnostic{
					Severity: "error",
					Code:     "home.verify.path_missing",
					Message:  fmt.Sprintf("%s is missing", state.TargetPath),
					Path:     state.TargetPath,
				})
			}
		}
	}
	return result, failures, nil
}

func representativeVerifyEntry(entry ResolvedEntry) bool {
	_, ok := representativeVerifyPaths[verifyPathKey{owner: entry.Owner, path: entry.Path}]
	return ok
}

type verifyPathKey struct {
	owner string
	path  string
}

var representativeVerifyPaths = map[verifyPathKey]struct{}{
	{owner: "public", path: ".zshrc"}:                {},
	{owner: "public", path: ".tmux.conf"}:            {},
	{owner: "public", path: ".claude/settings.json"}: {},
	{owner: "public", path: ".config/karabiner"}:     {},
	{owner: "private", path: ".zshenv"}:              {},
	{owner: "private", path: ".claude/skills"}:       {},
	{owner: "private", path: ".codex/config.toml"}:   {},
}

func Resolve(input string, opts Options) (ResolveResult, error) {
	topology, err := Load(opts)
	if err != nil {
		return ResolveResult{}, err
	}
	targetPath := normalizeTarget(input, topology.HomeDir)
	resolved, exists, isSymlink := resolveLive(targetPath)
	result := ResolveResult{
		Input:          input,
		TargetPath:     targetPath,
		Exists:         exists,
		IsSymlink:      isSymlink,
		ResolvedTarget: resolved,
		Diagnostics:    append([]report.Diagnostic{}, topology.Diagnostics...),
	}
	for _, entry := range topology.Entries {
		if samePath(entry.TargetPath, targetPath) {
			entryCopy := entry
			result.Entry = &entryCopy
			result.Owner = entry.Owner
			return result, nil
		}
	}
	for _, entry := range topology.Entries {
		if resolved != "" && samePath(entry.SourcePath, resolved) {
			entryCopy := entry
			result.Entry = &entryCopy
			result.Owner = entry.Owner
			return result, nil
		}
	}
	return result, nil
}

func InspectEntry(entry ResolvedEntry, modeOverride Mode) EntryState {
	mode := effectiveMode(entry.Mode, modeOverride)
	resolved, exists, isSymlink := resolveLive(entry.TargetPath)
	sourceExists := pathExists(entry.SourcePath)
	state := EntryState{
		Owner:          entry.Owner,
		Path:           entry.Path,
		Mode:           mode,
		Strategy:       entry.Strategy,
		SourcePath:     entry.SourcePath,
		TargetPath:     entry.TargetPath,
		Exists:         exists,
		IsSymlink:      isSymlink,
		ResolvedTarget: resolved,
	}
	if !sourceExists && mode != ModeWarn {
		state.Status = "source_missing"
		state.Action = "fix_manifest_or_source"
		return state
	}
	switch mode {
	case ModeWarn:
		state.Status = "warn"
		state.Action = "inspect"
	case ModeLink:
		switch {
		case !exists:
			state.Status = "missing"
			state.Action = "link"
		case samePath(resolved, entry.SourcePath):
			state.Status = "linked"
			state.Action = "skip"
		case isSymlink:
			state.Status = "wrong_link"
			state.Action = "backup_then_link"
		default:
			state.Status = "occupied"
			state.Action = "backup_then_link"
		}
	case ModeCopy:
		if exists {
			state.Status = "present"
			state.Action = "skip"
		} else {
			state.Status = "missing"
			state.Action = "copy"
		}
	case ModeMerge:
		if exists {
			state.Status = "present"
			state.Action = "merge"
		} else {
			state.Status = "missing"
			state.Action = "copy"
		}
	default:
		state.Status = "unsupported_mode"
		state.Action = "fix_manifest"
	}
	return state
}

func resolveEntries(homeDir string, manifest LoadedManifest) []ResolvedEntry {
	entries := make([]ResolvedEntry, 0, len(manifest.Entries))
	for _, entry := range manifest.Entries {
		cleanPath := strings.TrimPrefix(filepath.Clean(entry.Path), string(filepath.Separator))
		entries = append(entries, ResolvedEntry{
			Owner:        entry.Owner,
			Path:         cleanPath,
			Mode:         entry.Mode,
			Strategy:     entry.Strategy,
			SourcePath:   filepath.Join(manifest.RepoDir, cleanPath),
			TargetPath:   filepath.Join(homeDir, cleanPath),
			ManifestPath: manifest.ManifestPath,
		})
	}
	return entries
}

func resolveHome(explicit string) (string, error) {
	if explicit != "" {
		return filepath.Abs(explicit)
	}
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return homeDir, nil
}

func resolveRepos(publicRepo string, privateRepo string) (string, string, error) {
	if publicRepo == "" {
		publicRepo = os.Getenv("PUBLIC_REPO_DIR")
	}
	if privateRepo == "" {
		privateRepo = os.Getenv("PRIVATE_REPO_DIR")
	}
	if publicRepo == "" || privateRepo == "" {
		repo := findManifestRepo()
		switch filepath.Base(repo) {
		case "public-dotfiles":
			if publicRepo == "" {
				publicRepo = repo
			}
			if privateRepo == "" {
				privateRepo = siblingRepo(repo, "private-config")
			}
		case "private-config":
			if privateRepo == "" {
				privateRepo = repo
			}
			if publicRepo == "" {
				publicRepo = siblingRepo(repo, "public-dotfiles")
			}
		}
	}
	if privateRepo != "" {
		resolved, err := filepath.Abs(privateRepo)
		if err != nil {
			return "", "", err
		}
		privateRepo = resolved
	}
	if publicRepo == "" && privateRepo != "" {
		publicRepo = filepath.Join(filepath.Dir(privateRepo), "public-dotfiles")
	}
	if privateRepo == "" && publicRepo != "" {
		privateRepo = siblingRepo(publicRepo, "private-config")
	}
	if publicRepo != "" {
		resolved, err := filepath.Abs(publicRepo)
		if err != nil {
			return "", "", err
		}
		publicRepo = resolved
	}
	return publicRepo, privateRepo, nil
}

func siblingRepo(repoDir string, name string) string {
	candidate := filepath.Join(filepath.Dir(repoDir), name)
	if pathExists(candidate) {
		return candidate
	}
	return ""
}

func findManifestRepo() string {
	wd, err := os.Getwd()
	if err != nil {
		return ""
	}
	dir, err := filepath.Abs(wd)
	if err != nil {
		return ""
	}
	for {
		if ManifestExists(dir) {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return ""
		}
		dir = parent
	}
}

func normalizeTarget(input string, homeDir string) string {
	if input == "" {
		return homeDir
	}
	if input == "~" {
		return homeDir
	}
	if strings.HasPrefix(input, "~/") {
		return filepath.Join(homeDir, input[2:])
	}
	if filepath.IsAbs(input) {
		return filepath.Clean(input)
	}
	return filepath.Join(homeDir, input)
}

func resolveLive(path string) (string, bool, bool) {
	info, err := os.Lstat(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return "", false, false
		}
		return "", false, false
	}
	isSymlink := info.Mode()&os.ModeSymlink != 0
	if evaluated, err := filepath.EvalSymlinks(path); err == nil {
		return filepath.Clean(evaluated), true, isSymlink
	}
	if !isSymlink {
		return path, true, false
	}
	linkDir := filepath.Dir(path)
	if evaluatedDir, err := filepath.EvalSymlinks(linkDir); err == nil {
		linkDir = evaluatedDir
	}
	target, err := os.Readlink(path)
	if err != nil {
		return "", true, true
	}
	if !filepath.IsAbs(target) {
		target = filepath.Join(linkDir, target)
	}
	return filepath.Clean(target), true, true
}

func pathExists(path string) bool {
	_, err := os.Lstat(path)
	return err == nil
}

func samePath(a string, b string) bool {
	if a == "" || b == "" {
		return false
	}
	cleanA := canonicalPath(a)
	cleanB := canonicalPath(b)
	return filepath.Clean(cleanA) == filepath.Clean(cleanB)
}

func canonicalPath(path string) string {
	if evaluated, err := filepath.EvalSymlinks(path); err == nil {
		return evaluated
	}
	absolute, err := filepath.Abs(path)
	if err != nil {
		return filepath.Clean(path)
	}
	return absolute
}

func effectiveMode(mode Mode, override Mode) Mode {
	if override == "" {
		return mode
	}
	if mode == ModeLink || mode == ModeCopy {
		return override
	}
	return mode
}
