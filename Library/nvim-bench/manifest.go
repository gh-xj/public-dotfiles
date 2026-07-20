package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"slices"
)

type loadedManifest struct {
	Manifest
	Path   string
	Dir    string
	SHA256 string
}

func loadManifest(requested string) (loadedManifest, error) {
	path, err := resolveManifestPath(requested)
	if err != nil {
		return loadedManifest{}, err
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return loadedManifest{}, fmt.Errorf("read manifest: %w", err)
	}

	var manifest Manifest
	if err := json.Unmarshal(data, &manifest); err != nil {
		return loadedManifest{}, fmt.Errorf("parse manifest: %w", err)
	}
	if err := validateManifest(manifest); err != nil {
		return loadedManifest{}, err
	}

	sum := sha256.Sum256(data)
	return loadedManifest{
		Manifest: manifest,
		Path:     path,
		Dir:      filepath.Dir(path),
		SHA256:   hex.EncodeToString(sum[:]),
	}, nil
}

func resolveManifestPath(requested string) (string, error) {
	if requested != "" {
		path, err := filepath.Abs(requested)
		if err != nil {
			return "", err
		}
		if _, err := os.Stat(path); err != nil {
			return "", fmt.Errorf("manifest %q: %w", path, err)
		}
		return path, nil
	}

	candidates := []string{"scenarios.json", filepath.Join("Library", "nvim-bench", "scenarios.json")}
	if executable, err := os.Executable(); err == nil {
		candidates = append(candidates, filepath.Join(filepath.Dir(executable), "..", "scenarios.json"))
	}
	for _, candidate := range candidates {
		path, err := filepath.Abs(candidate)
		if err == nil {
			if _, statErr := os.Stat(path); statErr == nil {
				return filepath.Clean(path), nil
			}
		}
	}
	return "", fmt.Errorf("scenarios.json not found; pass --manifest")
}

func validateManifest(manifest Manifest) error {
	if manifest.SchemaVersion != manifestSchemaVersion {
		return fmt.Errorf("manifest schema_version must be %d", manifestSchemaVersion)
	}
	if manifest.Harness == "" {
		return fmt.Errorf("manifest harness is required")
	}
	seen := map[string]bool{}
	for _, scenario := range manifest.Scenarios {
		if scenario.ID == "" || scenario.Description == "" {
			return fmt.Errorf("every scenario needs id and description")
		}
		if seen[scenario.ID] {
			return fmt.Errorf("duplicate scenario id %q", scenario.ID)
		}
		seen[scenario.ID] = true
		if !slices.Contains([]string{"vim_enter", "lsp_ready"}, scenario.Probe) {
			return fmt.Errorf("scenario %q has unsupported probe %q", scenario.ID, scenario.Probe)
		}
		if scenario.Probe == "lsp_ready" && scenario.ExpectedClient == "" {
			return fmt.Errorf("scenario %q needs expected_client for lsp_ready", scenario.ID)
		}
		if scenario.Probe != "lsp_ready" && scenario.ExpectedClient != "" {
			return fmt.Errorf("scenario %q sets expected_client for non-LSP probe", scenario.ID)
		}
		if scenario.Fixture != "" && scenario.Generate != nil {
			return fmt.Errorf("scenario %q cannot set fixture and generate", scenario.ID)
		}
		if scenario.TimeoutMS <= 0 {
			return fmt.Errorf("scenario %q needs a positive timeout_ms", scenario.ID)
		}
	}
	return nil
}

func scenariosForSuite(manifest Manifest, suite string) []Scenario {
	var selected []Scenario
	for _, scenario := range manifest.Scenarios {
		if suite == "" || slices.Contains(scenario.Suites, suite) {
			selected = append(selected, scenario)
		}
	}
	return selected
}
