package home

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"configctl/internal/report"
)

const codexTopLevelKeysStrategy = "codex-top-level-keys"

type ApplyResult struct {
	HomeDir             string              `json:"home_dir"`
	Changed             bool                `json:"changed"`
	RepoRoots           map[string]string   `json:"repo_roots,omitempty"`
	Entries             []ApplyEntry        `json:"entries"`
	Counts              map[string]int      `json:"counts"`
	BackupRoots         []string            `json:"backup_roots,omitempty"`
	OperationReportPath string              `json:"operation_report_path,omitempty"`
	Diagnostics         []report.Diagnostic `json:"diagnostics"`
}

type ApplyEntry struct {
	EntryState
	Operation  string `json:"operation"`
	Changed    bool   `json:"changed"`
	BackupPath string `json:"backup_path,omitempty"`
}

func Apply(opts Options) (ApplyResult, error) {
	topology, err := Load(opts)
	if err != nil {
		return ApplyResult{}, err
	}
	now := opts.Now
	if now.IsZero() {
		now = time.Now()
	}
	result := ApplyResult{
		HomeDir:     topology.HomeDir,
		RepoRoots:   map[string]string{},
		Counts:      map[string]int{},
		Diagnostics: append([]report.Diagnostic{}, topology.Diagnostics...),
	}
	if topology.PublicRepo != "" {
		result.RepoRoots["public"] = topology.PublicRepo
	}
	if topology.PrivateRepo != "" {
		result.RepoRoots["private"] = topology.PrivateRepo
	}
	backupRoots := map[string]struct{}{}
	for _, entry := range topology.Entries {
		applied, err := applyEntry(topology, entry, opts, now)
		result.Entries = append(result.Entries, applied)
		result.Counts[applied.Operation]++
		if applied.Changed {
			result.Changed = true
		}
		if applied.BackupPath != "" {
			backupRoot := backupInstallRoot(applied.BackupPath)
			if backupRoot != "" {
				backupRoots[backupRoot] = struct{}{}
			}
		}
		if err != nil {
			result.Diagnostics = append(result.Diagnostics, report.Diagnostic{
				Severity: "error",
				Code:     "home.apply_failed",
				Message:  err.Error(),
				Path:     applied.TargetPath,
			})
			result.BackupRoots = sortedKeys(backupRoots)
			return result, err
		}
	}
	result.BackupRoots = sortedKeys(backupRoots)
	return result, nil
}

func applyEntry(topology Topology, entry ResolvedEntry, opts Options, now time.Time) (ApplyEntry, error) {
	state := InspectEntry(entry, opts.ModeOverride)
	applied := ApplyEntry{EntryState: state, Operation: state.Action}
	switch state.Mode {
	case ModeWarn:
		applied.Operation = "skip"
		return applied, nil
	case ModeLink:
		switch state.Status {
		case "linked":
			applied.Operation = "skip"
			return applied, nil
		case "missing":
			return applyLink(topology, entry, state, opts, now, false)
		case "wrong_link", "occupied":
			return applyLink(topology, entry, state, opts, now, true)
		default:
			return applied, fmt.Errorf("%s cannot be linked while status is %s", state.TargetPath, state.Status)
		}
	case ModeCopy:
		switch state.Status {
		case "present":
			applied.Operation = "skip"
			return applied, nil
		case "missing":
			return applyCopy(entry, state, opts)
		default:
			return applied, fmt.Errorf("%s cannot be copied while status is %s", state.TargetPath, state.Status)
		}
	case ModeMerge:
		switch state.Status {
		case "present":
			return applyMerge(topology, entry, state, opts, now)
		case "missing":
			return applyCopy(entry, state, opts)
		default:
			return applied, fmt.Errorf("%s cannot be merged while status is %s", state.TargetPath, state.Status)
		}
	default:
		return applied, fmt.Errorf("%s has unsupported mode %q", state.TargetPath, state.Mode)
	}
}

func applyLink(topology Topology, entry ResolvedEntry, state EntryState, opts Options, now time.Time, backup bool) (ApplyEntry, error) {
	operation := "link"
	applied := ApplyEntry{EntryState: state, Operation: operation, Changed: true}
	if backup {
		operation = "backup_then_link"
		applied.Operation = operation
		backupPath, err := backupTarget(topology, entry, state, now, opts.DryRun)
		if err != nil {
			return applied, err
		}
		applied.BackupPath = backupPath
	}
	if opts.DryRun {
		return applied, nil
	}
	if err := os.MkdirAll(filepath.Dir(state.TargetPath), 0o755); err != nil {
		return applied, err
	}
	return applied, os.Symlink(state.SourcePath, state.TargetPath)
}

func applyCopy(entry ResolvedEntry, state EntryState, opts Options) (ApplyEntry, error) {
	applied := ApplyEntry{EntryState: state, Operation: "copy", Changed: true}
	if opts.DryRun {
		return applied, nil
	}
	if err := os.MkdirAll(filepath.Dir(state.TargetPath), 0o755); err != nil {
		return applied, err
	}
	return applied, copyPath(entry.SourcePath, state.TargetPath)
}

func applyMerge(topology Topology, entry ResolvedEntry, state EntryState, opts Options, now time.Time) (ApplyEntry, error) {
	applied := ApplyEntry{EntryState: state, Operation: "merge"}
	if entry.Strategy != codexTopLevelKeysStrategy {
		return applied, fmt.Errorf("%s uses unsupported merge strategy %q", state.TargetPath, entry.Strategy)
	}
	toPrepend, err := missingTopLevelAssignments(state.SourcePath, state.TargetPath)
	if err != nil {
		return applied, err
	}
	if len(toPrepend) == 0 {
		applied.Operation = "skip"
		return applied, nil
	}
	applied.Changed = true
	backupPath, err := backupTarget(topology, entry, state, now, opts.DryRun)
	if err != nil {
		return applied, err
	}
	applied.BackupPath = backupPath
	if opts.DryRun {
		return applied, nil
	}
	existing, err := os.ReadFile(backupPath)
	if err != nil {
		return applied, err
	}
	content := strings.Join(toPrepend, "\n") + "\n\n" + strings.TrimLeft(string(existing), "\r\n")
	info, err := os.Stat(backupPath)
	if err != nil {
		return applied, err
	}
	if err := os.MkdirAll(filepath.Dir(state.TargetPath), 0o755); err != nil {
		return applied, err
	}
	return applied, os.WriteFile(state.TargetPath, []byte(content), info.Mode().Perm())
}

func backupTarget(topology Topology, entry ResolvedEntry, state EntryState, now time.Time, dryRun bool) (string, error) {
	root := backupOwnerRoot(topology, entry, state)
	rel, err := filepath.Rel(topology.HomeDir, state.TargetPath)
	if err != nil || strings.HasPrefix(rel, "..") {
		rel = filepath.Base(state.TargetPath)
	}
	backupPath := filepath.Join(root, ".install-backups", now.Format("20060102-150405"), rel)
	if dryRun {
		return backupPath, nil
	}
	if err := os.MkdirAll(filepath.Dir(backupPath), 0o755); err != nil {
		return backupPath, err
	}
	return backupPath, os.Rename(state.TargetPath, backupPath)
}

func backupOwnerRoot(topology Topology, entry ResolvedEntry, state EntryState) string {
	ownedPath := state.ResolvedTarget
	if ownedPath == "" {
		ownedPath = state.TargetPath
	}
	if topology.PrivateRepo != "" && pathWithinDir(ownedPath, topology.PrivateRepo) {
		return topology.PrivateRepo
	}
	if topology.PublicRepo != "" && pathWithinDir(ownedPath, topology.PublicRepo) {
		return topology.PublicRepo
	}
	return filepath.Dir(filepath.Dir(entry.ManifestPath))
}

func backupInstallRoot(path string) string {
	clean := filepath.Clean(path)
	parts := strings.Split(clean, string(filepath.Separator))
	for i := 0; i < len(parts)-1; i++ {
		if parts[i] != ".install-backups" {
			continue
		}
		root := strings.Join(parts[:i+2], string(filepath.Separator))
		if filepath.IsAbs(clean) && !strings.HasPrefix(root, string(filepath.Separator)) {
			root = string(filepath.Separator) + root
		}
		return filepath.Clean(root)
	}
	return ""
}

func pathWithinDir(path string, dir string) bool {
	rel, err := filepath.Rel(canonicalPath(dir), canonicalPath(path))
	return err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

func copyPath(src string, dst string) error {
	info, err := os.Lstat(src)
	if err != nil {
		return err
	}
	if info.Mode()&os.ModeSymlink != 0 {
		target, err := os.Readlink(src)
		if err != nil {
			return err
		}
		return os.Symlink(target, dst)
	}
	if info.IsDir() {
		return copyDir(src, dst, info.Mode().Perm())
	}
	return copyFile(src, dst, info.Mode().Perm())
}

func copyDir(src string, dst string, perm os.FileMode) error {
	if err := os.MkdirAll(dst, perm); err != nil {
		return err
	}
	entries, err := os.ReadDir(src)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		if err := copyPath(filepath.Join(src, entry.Name()), filepath.Join(dst, entry.Name())); err != nil {
			return err
		}
	}
	return nil
}

func copyFile(src string, dst string, perm os.FileMode) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_EXCL|os.O_WRONLY, perm)
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, in)
	return err
}

func missingTopLevelAssignments(src string, dst string) ([]string, error) {
	srcLines, err := topLevelAssignments(src)
	if err != nil {
		return nil, err
	}
	dstLines, err := topLevelAssignments(dst)
	if err != nil {
		return nil, err
	}
	existing := map[string]struct{}{}
	for _, line := range dstLines {
		existing[topLevelKey(line)] = struct{}{}
	}
	var missing []string
	for _, line := range srcLines {
		if _, ok := existing[topLevelKey(line)]; !ok {
			missing = append(missing, line)
		}
	}
	return missing, nil
}

func topLevelAssignments(path string) ([]string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var assignments []string
	for _, line := range strings.Split(string(data), "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		if strings.HasPrefix(trimmed, "[") {
			break
		}
		if topLevelKey(trimmed) != "" {
			assignments = append(assignments, line)
		}
	}
	return assignments, nil
}

func topLevelKey(line string) string {
	before, _, ok := strings.Cut(line, "=")
	if !ok {
		return ""
	}
	key := strings.TrimSpace(before)
	if key == "" || strings.ContainsAny(key, "[]") {
		return ""
	}
	return key
}

func sortedKeys(values map[string]struct{}) []string {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}
