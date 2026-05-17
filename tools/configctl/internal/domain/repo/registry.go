package repo

import (
	"fmt"
	"os"
	"path/filepath"

	"configctl/internal/report"

	"github.com/BurntSushi/toml"
)

const (
	RegistrySchemaVersion = "configctl.repos.v1"
	OverlaySchemaVersion  = "configctl.repos.overlay.v1"
)

type Registry struct {
	SchemaVersion  string              `toml:"schema_version" json:"schema_version"`
	PrivateOverlay string              `toml:"private_overlay" json:"private_overlay,omitempty"`
	Repos          []Definition        `toml:"repos" json:"repos"`
	Overlay        OverlayStatus       `json:"overlay"`
	Diagnostics    []report.Diagnostic `json:"diagnostics,omitempty"`
}

type Definition struct {
	Name     string `toml:"name" json:"name"`
	Owner    string `toml:"owner" json:"owner"`
	Path     string `toml:"path" json:"path"`
	Required bool   `toml:"required" json:"required"`
}

type OverlayStatus struct {
	Path   string `json:"path,omitempty"`
	Exists bool   `json:"exists"`
}

type overlayFile struct {
	SchemaVersion string              `toml:"schema_version"`
	Repos         []overlayDefinition `toml:"repos"`
}

type overlayDefinition struct {
	Name     string `toml:"name"`
	Owner    string `toml:"owner"`
	Path     string `toml:"path"`
	Required *bool  `toml:"required"`
}

func LoadRegistry(path string) (Registry, []report.Diagnostic, error) {
	registryPath, err := filepath.Abs(path)
	if err != nil {
		return Registry{}, nil, err
	}
	var registry Registry
	if _, err := toml.DecodeFile(registryPath, &registry); err != nil {
		diagnostic := report.Diagnostic{
			Severity: "error",
			Code:     "repo.registry_load_failed",
			Message:  err.Error(),
			Path:     registryPath,
		}
		return registry, []report.Diagnostic{diagnostic}, err
	}

	baseDir := filepath.Dir(registryPath)
	registry.Repos = normalizeDefinitions(baseDir, registry.Repos)
	var diagnostics []report.Diagnostic
	if registry.PrivateOverlay != "" {
		overlayPath := resolvePath(baseDir, registry.PrivateOverlay)
		registry.PrivateOverlay = overlayPath
		registry.Overlay.Path = overlayPath
		overlayDiagnostics, err := loadOverlay(overlayPath, &registry)
		diagnostics = append(diagnostics, overlayDiagnostics...)
		if err != nil {
			return registry, diagnostics, err
		}
	}
	diagnostics = append(diagnostics, validateRegistry(registryPath, &registry)...)
	registry.Diagnostics = diagnostics
	if diagnosticsHaveErrors(diagnostics) {
		return registry, diagnostics, fmt.Errorf("repo registry validation failed: %s", registryPath)
	}
	return registry, diagnostics, nil
}

func validateRegistry(path string, registry *Registry) []report.Diagnostic {
	var diagnostics []report.Diagnostic
	if registry.SchemaVersion != RegistrySchemaVersion {
		diagnostics = append(diagnostics, report.Diagnostic{
			Severity: "error",
			Code:     "repo.registry_schema_invalid",
			Message:  fmt.Sprintf("repo registry schema %q is not supported", registry.SchemaVersion),
			Path:     path,
		})
	}
	seen := map[string]struct{}{}
	for i, repo := range registry.Repos {
		location := fmt.Sprintf("%s repo %d", path, i+1)
		if repo.Name == "" {
			diagnostics = append(diagnostics, report.Diagnostic{
				Severity: "error",
				Code:     "repo.registry.name_missing",
				Message:  location + " has no name",
				Path:     path,
			})
			continue
		}
		if _, ok := seen[repo.Name]; ok {
			diagnostics = append(diagnostics, report.Diagnostic{
				Severity: "error",
				Code:     "repo.registry.duplicate_name",
				Message:  "duplicate repo " + repo.Name,
				Path:     path,
			})
		}
		seen[repo.Name] = struct{}{}
		if repo.Owner == "" {
			diagnostics = append(diagnostics, report.Diagnostic{
				Severity: "error",
				Code:     "repo.registry.owner_missing",
				Message:  location + " has no owner",
				Path:     path,
			})
		}
		if repo.Path == "" {
			diagnostics = append(diagnostics, report.Diagnostic{
				Severity: "error",
				Code:     "repo.registry.path_missing",
				Message:  location + " has no path",
				Path:     path,
			})
		}
	}
	return diagnostics
}

func loadOverlay(path string, registry *Registry) ([]report.Diagnostic, error) {
	info, err := os.Stat(path)
	if err != nil {
		if os.IsNotExist(err) {
			registry.Overlay.Exists = false
			return nil, nil
		}
		diagnostic := report.Diagnostic{
			Severity: "error",
			Code:     "repo.overlay_stat_failed",
			Message:  err.Error(),
			Path:     path,
		}
		return []report.Diagnostic{diagnostic}, err
	}
	if info.IsDir() {
		diagnostic := report.Diagnostic{
			Severity: "error",
			Code:     "repo.overlay_path_is_directory",
			Message:  "private repo overlay path is a directory",
			Path:     path,
		}
		return []report.Diagnostic{diagnostic}, fmt.Errorf("%s is a directory", path)
	}

	var overlay overlayFile
	if _, err := toml.DecodeFile(path, &overlay); err != nil {
		diagnostic := report.Diagnostic{
			Severity: "error",
			Code:     "repo.overlay_load_failed",
			Message:  err.Error(),
			Path:     path,
		}
		return []report.Diagnostic{diagnostic}, err
	}
	registry.Overlay.Exists = true
	if overlay.SchemaVersion != OverlaySchemaVersion {
		diagnostic := report.Diagnostic{
			Severity: "error",
			Code:     "repo.overlay_schema_invalid",
			Message:  fmt.Sprintf("repo overlay schema %q is not supported", overlay.SchemaVersion),
			Path:     path,
		}
		return []report.Diagnostic{diagnostic}, fmt.Errorf("repo overlay schema %q is not supported", overlay.SchemaVersion)
	}
	mergeOverlay(filepath.Dir(path), registry, overlay.Repos)
	return nil, nil
}

func mergeOverlay(baseDir string, registry *Registry, overlayRepos []overlayDefinition) {
	index := map[string]int{}
	for i, repo := range registry.Repos {
		index[repo.Name] = i
	}
	for _, overlayRepo := range overlayRepos {
		definition := Definition{
			Name:  overlayRepo.Name,
			Owner: overlayRepo.Owner,
			Path:  resolvePath(baseDir, overlayRepo.Path),
		}
		if overlayRepo.Required != nil {
			definition.Required = *overlayRepo.Required
		}
		if i, ok := index[overlayRepo.Name]; ok {
			if overlayRepo.Owner == "" {
				definition.Owner = registry.Repos[i].Owner
			}
			if overlayRepo.Path == "" {
				definition.Path = registry.Repos[i].Path
			}
			if overlayRepo.Required == nil {
				definition.Required = registry.Repos[i].Required
			}
			registry.Repos[i] = definition
			continue
		}
		registry.Repos = append(registry.Repos, definition)
	}
}

func normalizeDefinitions(baseDir string, repos []Definition) []Definition {
	out := make([]Definition, 0, len(repos))
	for _, repo := range repos {
		repo.Path = resolvePath(baseDir, repo.Path)
		out = append(out, repo)
	}
	return out
}

func resolvePath(baseDir string, path string) string {
	if path == "" {
		return ""
	}
	if filepath.IsAbs(path) {
		return filepath.Clean(path)
	}
	return filepath.Clean(filepath.Join(baseDir, path))
}

func diagnosticsHaveErrors(diagnostics []report.Diagnostic) bool {
	for _, diagnostic := range diagnostics {
		if diagnostic.Severity == "error" {
			return true
		}
	}
	return false
}
