package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

type doctorCheck struct {
	Name     string `json:"name"`
	Status   string `json:"status"`
	Detail   string `json:"detail"`
	Required bool   `json:"required"`
}

type doctorReport struct {
	SchemaVersion int           `json:"schema_version"`
	Status        string        `json:"status"`
	Checks        []doctorCheck `json:"checks"`
}

func (DoctorCmd) Run(cli *CLI) error {
	report := doctorReport{SchemaVersion: resultSchemaVersion, Status: "ok"}
	manifest, manifestErr := loadManifest(cli.Manifest)
	report.Checks = append(report.Checks, checkPath("manifest", manifest.Path, manifestErr, true))

	for _, name := range []string{cli.Nvim, "hyperfine"} {
		path, err := exec.LookPath(name)
		report.Checks = append(report.Checks, checkPath(name, path, err, true))
	}
	if path, err := exec.LookPath(cli.Nvim); err == nil {
		version, versionErr := commandOutput(path, "--version")
		if versionErr == nil {
			version = strings.Split(strings.TrimSpace(version), "\n")[0]
		}
		report.Checks = append(report.Checks, checkPath("nvim-version", version, versionErr, true))
	}
	if manifestErr == nil {
		harness := filepath.Join(manifest.Dir, manifest.Harness)
		_, err := os.Stat(harness)
		report.Checks = append(report.Checks, checkPath("lua-harness", harness, err, true))
	}

	nvimPaths := executablePaths(cli.Nvim)
	check := doctorCheck{Name: "nvim-path-identity", Status: "ok", Detail: strings.Join(nvimPaths, ", ")}
	if len(nvimPaths) > 1 {
		check.Status = "warning"
		check.Detail = "multiple executables on PATH: " + check.Detail
	}
	report.Checks = append(report.Checks, check)

	for _, check := range report.Checks {
		if check.Required && check.Status == "error" {
			report.Status = "error"
		}
	}

	if cli.JSON {
		return writeJSON(os.Stdout, report)
	}
	for _, check := range report.Checks {
		fmt.Printf("%-18s %-7s %s\n", check.Name, check.Status, check.Detail)
	}
	if report.Status != "ok" {
		return fmt.Errorf("required benchmark prerequisites are missing")
	}
	return nil
}

func checkPath(name, path string, err error, required bool) doctorCheck {
	if err != nil {
		return doctorCheck{Name: name, Status: "error", Detail: err.Error(), Required: required}
	}
	return doctorCheck{Name: name, Status: "ok", Detail: path, Required: required}
}

func executablePaths(name string) []string {
	if strings.ContainsRune(name, filepath.Separator) {
		path, err := filepath.Abs(name)
		if err == nil {
			if info, statErr := os.Stat(path); statErr == nil && !info.IsDir() {
				return []string{path}
			}
		}
		return nil
	}
	seen := map[string]bool{}
	var paths []string
	for _, dir := range filepath.SplitList(os.Getenv("PATH")) {
		candidate := filepath.Join(dir, name)
		if info, err := os.Stat(candidate); err == nil && !info.IsDir() {
			path, _ := filepath.Abs(candidate)
			if !seen[path] {
				seen[path] = true
				paths = append(paths, path)
			}
		}
	}
	return paths
}

func (cmd ListCmd) Run(cli *CLI) error {
	manifest, err := loadManifest(cli.Manifest)
	if err != nil {
		return err
	}
	scenarios := scenariosForSuite(manifest.Manifest, cmd.Suite)
	if len(scenarios) == 0 {
		return fmt.Errorf("suite %q has no scenarios", cmd.Suite)
	}
	if cli.JSON {
		return json.NewEncoder(os.Stdout).Encode(struct {
			SchemaVersion int        `json:"schema_version"`
			Scenarios     []Scenario `json:"scenarios"`
		}{resultSchemaVersion, scenarios})
	}
	for _, scenario := range scenarios {
		fmt.Printf("%-22s %-10s %s\n", scenario.ID, scenario.Probe, scenario.Description)
	}
	return nil
}
