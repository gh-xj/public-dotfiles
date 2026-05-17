package home

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"configctl/internal/report"

	"github.com/BurntSushi/toml"
)

const manifestRelPath = "configctl/home.toml"

type Mode string

const (
	ModeLink  Mode = "link"
	ModeCopy  Mode = "copy"
	ModeMerge Mode = "merge"
	ModeWarn  Mode = "warn"
)

type Manifest struct {
	Entries []Entry `toml:"entries" json:"entries"`
}

type Entry struct {
	Owner    string `toml:"owner" json:"owner"`
	Path     string `toml:"path" json:"path"`
	Mode     Mode   `toml:"mode" json:"mode"`
	Strategy string `toml:"strategy" json:"strategy,omitempty"`
}

type LoadedManifest struct {
	Owner        string              `json:"owner"`
	RepoDir      string              `json:"repo_dir"`
	ManifestPath string              `json:"manifest_path"`
	Entries      []Entry             `json:"entries"`
	Diagnostics  []report.Diagnostic `json:"diagnostics,omitempty"`
}

func LoadManifest(owner string, repoDir string) (LoadedManifest, []report.Diagnostic, error) {
	manifestPath := filepath.Join(repoDir, manifestRelPath)
	loaded := LoadedManifest{
		Owner:        owner,
		RepoDir:      repoDir,
		ManifestPath: manifestPath,
	}
	var manifest Manifest
	if _, err := toml.DecodeFile(manifestPath, &manifest); err != nil {
		diagnostic := report.Diagnostic{
			Severity: "error",
			Code:     "home.manifest_load_failed",
			Message:  err.Error(),
			Path:     manifestPath,
		}
		return loaded, []report.Diagnostic{diagnostic}, err
	}
	diagnostics := validateEntries(owner, repoDir, manifestPath, manifest.Entries)
	loaded.Entries = normalizeEntries(owner, manifest.Entries)
	loaded.Diagnostics = diagnostics
	if diagnosticsHaveErrors(diagnostics) {
		return loaded, diagnostics, fmt.Errorf("manifest validation failed: %s", manifestPath)
	}
	return loaded, diagnostics, nil
}

func ManifestExists(repoDir string) bool {
	info, err := os.Stat(filepath.Join(repoDir, manifestRelPath))
	return err == nil && !info.IsDir()
}

func normalizeEntries(owner string, entries []Entry) []Entry {
	out := make([]Entry, 0, len(entries))
	for _, entry := range entries {
		if entry.Owner == "" {
			entry.Owner = owner
		}
		if entry.Mode == "" {
			entry.Mode = ModeLink
		}
		entry.Path = strings.TrimPrefix(filepath.Clean(entry.Path), string(filepath.Separator))
		out = append(out, entry)
	}
	return out
}

func validateEntries(owner string, repoDir string, manifestPath string, entries []Entry) []report.Diagnostic {
	var diagnostics []report.Diagnostic
	seen := map[string]struct{}{}
	for i, entry := range entries {
		location := fmt.Sprintf("%s entry %d", manifestPath, i+1)
		if entry.Path == "" {
			diagnostics = append(diagnostics, report.Diagnostic{
				Severity: "error",
				Code:     "home.manifest.path_missing",
				Message:  location + " has no path",
				Path:     manifestPath,
			})
			continue
		}
		cleanPath := strings.TrimPrefix(filepath.Clean(entry.Path), string(filepath.Separator))
		if cleanPath == "." || strings.HasPrefix(cleanPath, ".."+string(filepath.Separator)) || cleanPath == ".." {
			diagnostics = append(diagnostics, report.Diagnostic{
				Severity: "error",
				Code:     "home.manifest.path_invalid",
				Message:  location + " path must stay within $HOME",
				Path:     entry.Path,
			})
		}
		if _, exists := seen[cleanPath]; exists {
			diagnostics = append(diagnostics, report.Diagnostic{
				Severity: "error",
				Code:     "home.manifest.duplicate_path",
				Message:  "duplicate home entry " + cleanPath,
				Path:     entry.Path,
			})
		}
		seen[cleanPath] = struct{}{}
		if entry.Owner != "" && entry.Owner != owner {
			diagnostics = append(diagnostics, report.Diagnostic{
				Severity: "error",
				Code:     "home.manifest.owner_mismatch",
				Message:  fmt.Sprintf("%s owner is %q, expected %q", location, entry.Owner, owner),
				Path:     entry.Path,
			})
		}
		switch entry.Mode {
		case "", ModeLink, ModeCopy, ModeMerge, ModeWarn:
		default:
			diagnostics = append(diagnostics, report.Diagnostic{
				Severity: "error",
				Code:     "home.manifest.mode_invalid",
				Message:  fmt.Sprintf("%s mode %q is not supported", location, entry.Mode),
				Path:     entry.Path,
			})
		}
		if _, err := os.Lstat(filepath.Join(repoDir, cleanPath)); err != nil && entry.Mode != ModeWarn {
			diagnostics = append(diagnostics, report.Diagnostic{
				Severity: "warning",
				Code:     "home.source_missing",
				Message:  "manifest source path is missing",
				Path:     filepath.Join(repoDir, cleanPath),
			})
		}
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
