package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

func (cmd RunCmd) Run(cli *CLI) error {
	if cmd.Runs < 1 || cmd.Warmup < 0 {
		return fmt.Errorf("runs must be positive and warmup cannot be negative")
	}
	manifest, err := loadManifest(cli.Manifest)
	if err != nil {
		return err
	}
	scenarios := scenariosForSuite(manifest.Manifest, cmd.Suite)
	if len(scenarios) == 0 {
		return fmt.Errorf("suite %q has no scenarios", cmd.Suite)
	}
	if _, err := exec.LookPath("hyperfine"); err != nil {
		return fmt.Errorf("hyperfine is required: %w", err)
	}
	configHome, err := resolveConfigHome(cli.ConfigHome, manifest)
	if err != nil {
		return err
	}

	environment, err := collectEnvironment(cli.Nvim, configHome, manifest)
	if err != nil {
		return err
	}
	now := time.Now().UTC()
	run := RunResult{
		SchemaVersion: resultSchemaVersion,
		RunID:         now.Format("20060102T150405.000000000Z"),
		CreatedAt:     now,
		Suite:         cmd.Suite,
		Runs:          cmd.Runs,
		Warmup:        cmd.Warmup,
		Environment:   environment,
	}

	failed := false
	for _, scenario := range scenarios {
		if cli.Verbose {
			fmt.Fprintf(os.Stderr, "running %s (%s)\n", scenario.ID, scenario.Probe)
		}
		result := runScenario(cmd, manifest, scenario, environment.NvimPath, configHome, cli.Verbose)
		if result.Status != "passed" {
			failed = true
		}
		run.Scenarios = append(run.Scenarios, result)
	}

	output, err := resultPath(cmd.Output, run.RunID)
	if err != nil {
		return err
	}
	if err := writeJSONFile(output, run); err != nil {
		return err
	}
	if cli.JSON {
		if err := writeJSON(os.Stdout, run); err != nil {
			return err
		}
	} else {
		printRunSummary(run)
		fmt.Println("result:", output)
	}
	if failed {
		return fmt.Errorf("one or more scenarios failed; result saved to %s", output)
	}
	return nil
}

func runScenario(cmd RunCmd, manifest loadedManifest, scenario Scenario, nvimPath, configHome string, verbose bool) ScenarioResult {
	result := ScenarioResult{
		ID:          scenario.ID,
		Description: scenario.Description,
		Probe:       scenario.Probe,
		Status:      "failed",
		BudgetMS:    scenario.BudgetMS,
	}

	tempDir, err := os.MkdirTemp("", "nvim-bench-")
	if err != nil {
		result.Error = err.Error()
		return result
	}
	defer os.RemoveAll(tempDir)

	fixture, err := prepareFixture(manifest, scenario, tempDir)
	if err != nil {
		result.Error = err.Error()
		return result
	}
	probePath := filepath.Join(tempDir, "probe.json")
	hyperfinePath := filepath.Join(tempDir, "hyperfine.json")
	harnessPath := filepath.Join(manifest.Dir, manifest.Harness)

	args := []string{"--headless", "-i", "NONE", "-n"}
	args = append(args, scenario.NvimArgs...)
	args = append(args, "--cmd", "lua dofile(vim.env.NVIM_BENCH_HARNESS)")
	if fixture != "" {
		args = append(args, fixture)
	}

	env := []string{
		"XDG_CONFIG_HOME=" + configHome,
		"NVIM_BENCH_HARNESS=" + harnessPath,
		"NVIM_BENCH_PROBE=" + scenario.Probe,
		"NVIM_BENCH_OUTPUT=" + probePath,
		"NVIM_BENCH_TIMEOUT_MS=" + strconv.Itoa(scenario.TimeoutMS),
	}
	command := shellCommand(env, nvimPath, args)
	if verbose {
		fmt.Fprintln(os.Stderr, command)
	}

	hfArgs := []string{
		"--warmup", strconv.Itoa(cmd.Warmup),
		"--runs", strconv.Itoa(cmd.Runs),
		"--style", "basic",
		"--export-json", hyperfinePath,
		"--command-name", scenario.ID,
		command,
	}
	hf := exec.Command("hyperfine", hfArgs...)
	var hyperfineOutput bytes.Buffer
	if verbose {
		hf.Stdout = os.Stderr
		hf.Stderr = os.Stderr
	} else {
		hf.Stdout = &hyperfineOutput
		hf.Stderr = &hyperfineOutput
	}
	runErr := hf.Run()

	probe, probeErr := readProbe(probePath)
	if probeErr == nil {
		result.LoadedPlugins = probe.LoadedPlugins
		result.Clients = probe.Clients
		result.ProbeElapsed = probe.ElapsedMS
		if probe.Status != "passed" && result.Error == "" {
			result.Error = probe.Error
		}
	}
	if runErr != nil {
		if result.Error == "" {
			result.Error = strings.TrimSpace(hyperfineOutput.String())
			if result.Error == "" {
				result.Error = runErr.Error()
			}
		}
		return result
	}

	data, err := os.ReadFile(hyperfinePath)
	if err != nil {
		result.Error = fmt.Sprintf("read hyperfine result: %v", err)
		return result
	}
	var output HyperfineOutput
	if err := json.Unmarshal(data, &output); err != nil || len(output.Results) != 1 {
		result.Error = "invalid hyperfine result"
		return result
	}
	stats := output.Results[0]
	result.SamplesMS = secondsToMilliseconds(stats.Times)
	result.MeanMS = stats.Mean * 1000
	result.MedianMS = percentile(result.SamplesMS, 0.50)
	result.P95MS = percentile(result.SamplesMS, 0.95)
	result.StddevMS = stats.Stddev * 1000
	result.MinMS = stats.Min * 1000
	result.MaxMS = stats.Max * 1000
	result.Status = "passed"
	if scenario.BudgetMS > 0 {
		passed := result.P95MS <= scenario.BudgetMS
		result.BudgetPassed = &passed
		if !passed && cmd.Budgets {
			result.Status = "failed"
			result.Error = fmt.Sprintf("p95 %.1f ms exceeds %.1f ms budget", result.P95MS, scenario.BudgetMS)
		}
	}
	return result
}

func prepareFixture(manifest loadedManifest, scenario Scenario, tempDir string) (string, error) {
	if scenario.Fixture != "" {
		path := filepath.Join(manifest.Dir, scenario.Fixture)
		if _, err := os.Stat(path); err != nil {
			return "", fmt.Errorf("fixture for %s: %w", scenario.ID, err)
		}
		return path, nil
	}
	if scenario.Generate == nil {
		return "", nil
	}
	if scenario.Generate.Lines <= 0 || scenario.Generate.Content == "" {
		return "", fmt.Errorf("scenario %s has invalid generated fixture", scenario.ID)
	}
	path := filepath.Join(tempDir, "fixture"+scenario.Generate.Extension)
	file, err := os.Create(path)
	if err != nil {
		return "", err
	}
	writer := bufio.NewWriter(file)
	for range scenario.Generate.Lines {
		if _, err := writer.WriteString(scenario.Generate.Content + "\n"); err != nil {
			file.Close()
			return "", err
		}
	}
	if err := writer.Flush(); err != nil {
		file.Close()
		return "", err
	}
	if err := file.Close(); err != nil {
		return "", err
	}
	return path, nil
}
