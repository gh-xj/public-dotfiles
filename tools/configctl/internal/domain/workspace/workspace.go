package workspace

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"configctl/internal/domain/repo"
	"configctl/internal/report"

	"github.com/BurntSushi/toml"
)

const (
	SchemaVersion = "configctl.workspaces.v1"
	ModeLink      = "link"
)

type Options struct {
	ManifestPath string
	Name         string
	DryRun       bool
}

type Manifest struct {
	SchemaVersion string       `toml:"schema_version" json:"schema_version"`
	Workspaces    []Definition `toml:"workspaces" json:"workspaces"`
}

type Definition struct {
	Name     string `toml:"name" json:"name"`
	Local    string `toml:"local" json:"local"`
	External string `toml:"external" json:"external"`
	Mode     string `toml:"mode" json:"mode"`
	Required bool   `toml:"required" json:"required"`
}

type LoadedManifest struct {
	Path        string              `json:"path"`
	Manifest    Manifest            `json:"manifest"`
	Diagnostics []report.Diagnostic `json:"diagnostics"`
}

type StatusResult struct {
	ManifestPath string              `json:"manifest_path"`
	Workspaces   []State             `json:"workspaces"`
	Counts       map[string]int      `json:"counts"`
	Diagnostics  []report.Diagnostic `json:"diagnostics"`
}

type State struct {
	Name                string `json:"name"`
	Local               string `json:"local"`
	External            string `json:"external"`
	Mode                string `json:"mode"`
	Required            bool   `json:"required"`
	LocalExists         bool   `json:"local_exists"`
	LocalIsSymlink      bool   `json:"local_is_symlink"`
	LocalResolved       string `json:"local_resolved,omitempty"`
	ExternalExists      bool   `json:"external_exists"`
	ExternalIsDir       bool   `json:"external_is_dir"`
	Status              string `json:"status"`
	Action              string `json:"action"`
	Changed             bool   `json:"changed,omitempty"`
	Operation           string `json:"operation,omitempty"`
	OperationReportPath string `json:"operation_report_path,omitempty"`
}

type LinkResult struct {
	State               State               `json:"state"`
	Changed             bool                `json:"changed"`
	DryRun              bool                `json:"dry_run"`
	OperationReportPath string              `json:"operation_report_path,omitempty"`
	Diagnostics         []report.Diagnostic `json:"diagnostics"`
}

func Status(opts Options) (StatusResult, error) {
	loaded, diagnostics, err := LoadManifest(opts.ManifestPath)
	result := StatusResult{
		ManifestPath: loaded.Path,
		Counts:       map[string]int{},
		Diagnostics:  append([]report.Diagnostic{}, diagnostics...),
	}
	if err != nil {
		return result, err
	}
	for _, definition := range selectedDefinitions(loaded.Manifest.Workspaces, opts.Name) {
		state := Inspect(definition)
		result.Workspaces = append(result.Workspaces, state)
		result.Counts[state.Status]++
		result.Diagnostics = append(result.Diagnostics, stateDiagnostics(state)...)
	}
	sort.Slice(result.Workspaces, func(i, j int) bool {
		return result.Workspaces[i].Name < result.Workspaces[j].Name
	})
	return result, nil
}

func Verify(opts Options) (StatusResult, []report.Diagnostic, error) {
	status, err := Status(opts)
	if err != nil {
		return status, nil, err
	}
	var failures []report.Diagnostic
	for _, state := range status.Workspaces {
		for _, diagnostic := range verifyState(state) {
			if diagnostic.Severity == "error" {
				failures = append(failures, diagnostic)
			}
		}
	}
	return status, failures, nil
}

func Link(opts Options) (LinkResult, error) {
	status, err := Status(Options{ManifestPath: opts.ManifestPath, Name: opts.Name})
	if err != nil {
		return LinkResult{Diagnostics: status.Diagnostics}, err
	}
	if opts.Name == "" {
		err := errors.New("workspace name is required")
		return LinkResult{Diagnostics: []report.Diagnostic{{
			Severity: "error",
			Code:     "workspace.name_required",
			Message:  err.Error(),
		}}}, err
	}
	if len(status.Workspaces) == 0 {
		err := fmt.Errorf("workspace %q not found", opts.Name)
		return LinkResult{Diagnostics: []report.Diagnostic{{
			Severity: "error",
			Code:     "workspace.not_found",
			Message:  err.Error(),
		}}}, err
	}
	state := status.Workspaces[0]
	result := LinkResult{
		State:       state,
		DryRun:      opts.DryRun,
		Diagnostics: append([]report.Diagnostic{}, status.Diagnostics...),
	}
	if state.Status == "linked" {
		result.State.Operation = "skip"
		return result, nil
	}
	if !state.ExternalExists || !state.ExternalIsDir {
		err := fmt.Errorf("%s external path is unavailable", state.Name)
		result.Diagnostics = append(result.Diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "workspace.external_unavailable",
			Message:  err.Error(),
			Path:     state.External,
		})
		return result, err
	}
	if state.LocalExists && !state.LocalIsSymlink {
		err := fmt.Errorf("%s local path is a real filesystem entry and will not be overwritten", state.Local)
		result.Diagnostics = append(result.Diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "workspace.local_occupied",
			Message:  err.Error(),
			Path:     state.Local,
		})
		return result, err
	}
	result.Changed = true
	result.State.Changed = true
	result.State.Operation = "link"
	if opts.DryRun {
		return result, nil
	}
	if state.LocalIsSymlink {
		if err := os.Remove(state.Local); err != nil {
			result.Diagnostics = append(result.Diagnostics, report.Diagnostic{
				Severity: "error",
				Code:     "workspace.unlink_failed",
				Message:  err.Error(),
				Path:     state.Local,
			})
			return result, err
		}
	}
	if err := os.MkdirAll(filepath.Dir(state.Local), 0o755); err != nil {
		result.Diagnostics = append(result.Diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "workspace.parent_create_failed",
			Message:  err.Error(),
			Path:     filepath.Dir(state.Local),
		})
		return result, err
	}
	if err := os.Symlink(state.External, state.Local); err != nil {
		result.Diagnostics = append(result.Diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "workspace.link_failed",
			Message:  err.Error(),
			Path:     state.Local,
		})
		return result, err
	}
	return result, nil
}

func LoadManifest(path string) (LoadedManifest, []report.Diagnostic, error) {
	if path == "" {
		defaultPath, err := DefaultManifestPath()
		if err != nil {
			diagnostic := report.Diagnostic{
				Severity: "error",
				Code:     "workspace.manifest_not_found",
				Message:  err.Error(),
			}
			return LoadedManifest{}, []report.Diagnostic{diagnostic}, err
		}
		path = defaultPath
	}
	abs, err := filepath.Abs(path)
	if err != nil {
		return LoadedManifest{}, nil, err
	}
	var manifest Manifest
	if _, err := toml.DecodeFile(abs, &manifest); err != nil {
		diagnostic := report.Diagnostic{
			Severity: "error",
			Code:     "workspace.manifest_load_failed",
			Message:  err.Error(),
			Path:     abs,
		}
		return LoadedManifest{Path: abs}, []report.Diagnostic{diagnostic}, err
	}
	diagnostics := validateManifest(abs, manifest)
	loaded := LoadedManifest{
		Path:        abs,
		Manifest:    normalizeManifest(manifest),
		Diagnostics: diagnostics,
	}
	if diagnosticsHaveErrors(diagnostics) {
		return loaded, diagnostics, fmt.Errorf("workspace manifest validation failed: %s", abs)
	}
	return loaded, diagnostics, nil
}

func DefaultManifestPath() (string, error) {
	registryPath, err := repo.DefaultRegistryPath()
	if err != nil {
		return "", err
	}
	return filepath.Join(repo.PublicRootFromRegistry(registryPath), "configctl", "workspaces.toml"), nil
}

func Inspect(definition Definition) State {
	localResolved, localExists, localIsSymlink := resolveLive(definition.Local)
	externalInfo, externalErr := os.Stat(definition.External)
	state := State{
		Name:           definition.Name,
		Local:          definition.Local,
		External:       definition.External,
		Mode:           definition.Mode,
		Required:       definition.Required,
		LocalExists:    localExists,
		LocalIsSymlink: localIsSymlink,
		LocalResolved:  localResolved,
		ExternalExists: externalErr == nil,
	}
	if externalErr == nil {
		state.ExternalIsDir = externalInfo.IsDir()
	}
	switch {
	case definition.Mode != ModeLink:
		state.Status = "unsupported_mode"
		state.Action = "fix_manifest"
	case !state.ExternalExists:
		state.Status = "external_missing"
		state.Action = "mount_external"
	case !state.ExternalIsDir:
		state.Status = "external_not_directory"
		state.Action = "fix_external"
	case !state.LocalExists:
		state.Status = "missing"
		state.Action = "link"
	case state.LocalIsSymlink && samePath(state.LocalResolved, state.External):
		state.Status = "linked"
		state.Action = "skip"
	case state.LocalIsSymlink:
		state.Status = "wrong_link"
		state.Action = "link"
	default:
		state.Status = "occupied"
		state.Action = "manual"
	}
	return state
}

func selectedDefinitions(definitions []Definition, name string) []Definition {
	if name == "" {
		return definitions
	}
	var selected []Definition
	for _, definition := range definitions {
		if definition.Name == name {
			selected = append(selected, definition)
		}
	}
	return selected
}

func validateManifest(path string, manifest Manifest) []report.Diagnostic {
	var diagnostics []report.Diagnostic
	if manifest.SchemaVersion != SchemaVersion {
		diagnostics = append(diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "workspace.manifest_schema_invalid",
			Message:  fmt.Sprintf("workspace manifest schema %q is not supported", manifest.SchemaVersion),
			Path:     path,
		})
	}
	seen := map[string]struct{}{}
	for i, definition := range manifest.Workspaces {
		location := fmt.Sprintf("%s workspace %d", path, i+1)
		if definition.Name == "" {
			diagnostics = append(diagnostics, report.Diagnostic{
				Severity: "error",
				Code:     "workspace.name_missing",
				Message:  location + " has no name",
				Path:     path,
			})
		}
		if _, ok := seen[definition.Name]; ok {
			diagnostics = append(diagnostics, report.Diagnostic{
				Severity: "error",
				Code:     "workspace.duplicate_name",
				Message:  "duplicate workspace " + definition.Name,
				Path:     path,
			})
		}
		seen[definition.Name] = struct{}{}
		if definition.Local == "" || !filepath.IsAbs(definition.Local) {
			diagnostics = append(diagnostics, report.Diagnostic{
				Severity: "error",
				Code:     "workspace.local_invalid",
				Message:  location + " local path must be absolute",
				Path:     definition.Local,
			})
		}
		if definition.External == "" || !filepath.IsAbs(definition.External) {
			diagnostics = append(diagnostics, report.Diagnostic{
				Severity: "error",
				Code:     "workspace.external_invalid",
				Message:  location + " external path must be absolute",
				Path:     definition.External,
			})
		}
		if definition.Mode != "" && definition.Mode != ModeLink {
			diagnostics = append(diagnostics, report.Diagnostic{
				Severity: "error",
				Code:     "workspace.mode_invalid",
				Message:  fmt.Sprintf("%s mode %q is not supported", location, definition.Mode),
				Path:     path,
			})
		}
	}
	return diagnostics
}

func normalizeManifest(manifest Manifest) Manifest {
	for i := range manifest.Workspaces {
		if manifest.Workspaces[i].Mode == "" {
			manifest.Workspaces[i].Mode = ModeLink
		}
		manifest.Workspaces[i].Local = filepath.Clean(manifest.Workspaces[i].Local)
		manifest.Workspaces[i].External = filepath.Clean(manifest.Workspaces[i].External)
	}
	return manifest
}

func verifyState(state State) []report.Diagnostic {
	var diagnostics []report.Diagnostic
	switch state.Status {
	case "linked":
		return nil
	case "external_missing":
		severity := "warning"
		if state.Required {
			severity = "error"
		}
		diagnostics = append(diagnostics, report.Diagnostic{
			Severity: severity,
			Code:     "workspace.external_missing",
			Message:  fmt.Sprintf("%s external path is missing", state.Name),
			Path:     state.External,
		})
	case "external_not_directory":
		diagnostics = append(diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "workspace.external_not_directory",
			Message:  fmt.Sprintf("%s external path is not a directory", state.Name),
			Path:     state.External,
		})
	case "missing", "wrong_link", "occupied", "unsupported_mode":
		diagnostics = append(diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "workspace.verify." + state.Status,
			Message:  fmt.Sprintf("%s workspace is %s", state.Name, strings.ReplaceAll(state.Status, "_", " ")),
			Path:     state.Local,
		})
	}
	return diagnostics
}

func stateDiagnostics(state State) []report.Diagnostic {
	diagnostics := verifyState(state)
	if len(diagnostics) == 0 {
		return nil
	}
	if state.Status == "external_missing" && !state.Required {
		return diagnostics
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
