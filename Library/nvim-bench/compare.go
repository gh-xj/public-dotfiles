package main

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"
)

func (cmd CompareCmd) Run(cli *CLI) error {
	before, err := readRunResult(cmd.Before)
	if err != nil {
		return fmt.Errorf("read before result: %w", err)
	}
	after, err := readRunResult(cmd.After)
	if err != nil {
		return fmt.Errorf("read after result: %w", err)
	}
	if !cmd.Incompatible {
		if err := compatibleRuns(before, after); err != nil {
			return err
		}
	}
	comparison := compareRuns(before, after, cmd.Percent, cmd.AbsoluteMS)
	if len(comparison.Scenarios) == 0 {
		return fmt.Errorf("results have no comparable scenarios")
	}
	if cli.JSON {
		if err := writeJSON(os.Stdout, comparison); err != nil {
			return err
		}
	} else {
		fmt.Printf("%-22s %10s %10s %10s %9s\n", "scenario", "before", "after", "delta", "status")
		for _, change := range comparison.Scenarios {
			status := "ok"
			if change.Regression {
				status = "REGRESS"
			}
			fmt.Printf("%-22s %8.1fms %8.1fms %+8.1fms %9s\n",
				change.ID, change.BeforeMS, change.AfterMS, change.DeltaMS, status)
			if change.Reason != "" {
				fmt.Printf("  %s\n", change.Reason)
			}
		}
	}
	if comparison.Regressions > 0 && !cmd.AllowFailure {
		return fmt.Errorf("%d scenario regressions exceeded both gates", comparison.Regressions)
	}
	return nil
}

func compatibleRuns(before, after RunResult) error {
	checks := []struct {
		name   string
		before string
		after  string
	}{
		{"operating system", before.Environment.OS, after.Environment.OS},
		{"architecture", before.Environment.Arch, after.Environment.Arch},
		{"OS version", before.Environment.OSVersion, after.Environment.OSVersion},
		{"CPU", before.Environment.CPU, after.Environment.CPU},
		{"Neovim version", before.Environment.NvimVersion, after.Environment.NvimVersion},
		{"Neovim executable", before.Environment.NvimResolvedPath, after.Environment.NvimResolvedPath},
		{"hyperfine version", before.Environment.HyperfineVersion, after.Environment.HyperfineVersion},
		{"scenario manifest", before.Environment.ManifestSHA256, after.Environment.ManifestSHA256},
		{"benchmark harness", before.Environment.HarnessSHA256, after.Environment.HarnessSHA256},
	}
	if before.Suite != after.Suite {
		return fmt.Errorf("incompatible suite: %q != %q (use --allow-incompatible to override)", before.Suite, after.Suite)
	}
	if before.Runs != after.Runs || before.Warmup != after.Warmup {
		return fmt.Errorf("incompatible sampling: runs/warmup %d/%d != %d/%d (use --allow-incompatible to override)",
			before.Runs, before.Warmup, after.Runs, after.Warmup)
	}
	for _, check := range checks {
		if check.before != check.after {
			return fmt.Errorf("incompatible %s: %q != %q (use --allow-incompatible to override)",
				check.name, check.before, check.after)
		}
	}
	return nil
}

func readRunResult(path string) (RunResult, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return RunResult{}, err
	}
	var result RunResult
	if err := json.Unmarshal(data, &result); err != nil {
		return RunResult{}, err
	}
	if result.SchemaVersion != resultSchemaVersion {
		return RunResult{}, fmt.Errorf("unsupported schema_version %d", result.SchemaVersion)
	}
	return result, nil
}

func compareRuns(before, after RunResult, percentGate, absoluteGate float64) Comparison {
	comparison := Comparison{
		SchemaVersion: resultSchemaVersion,
		BeforeRunID:   before.RunID,
		AfterRunID:    after.RunID,
		PercentGate:   percentGate,
		AbsoluteGate:  absoluteGate,
	}
	beforeByID := map[string]ScenarioResult{}
	for _, result := range before.Scenarios {
		beforeByID[result.ID] = result
	}
	for _, result := range after.Scenarios {
		baseline, ok := beforeByID[result.ID]
		if !ok {
			continue
		}
		change := ScenarioChange{
			ID:           result.ID,
			BeforeStatus: baseline.Status,
			AfterStatus:  result.Status,
			BeforeMS:     baseline.MedianMS,
			AfterMS:      result.MedianMS,
		}
		if baseline.Status == "passed" && result.Status != "passed" {
			change.Regression = true
			change.Reason = "candidate scenario failed: " + result.Error
			comparison.Regressions++
			comparison.Scenarios = append(comparison.Scenarios, change)
			continue
		}
		if baseline.Status != "passed" || result.Status != "passed" || baseline.MedianMS <= 0 {
			comparison.Scenarios = append(comparison.Scenarios, change)
			continue
		}
		delta := result.MedianMS - baseline.MedianMS
		percent := delta / baseline.MedianMS * 100
		regression := delta > absoluteGate && percent > percentGate
		if regression {
			comparison.Regressions++
		}
		change.DeltaMS = delta
		change.DeltaPct = percent
		change.Regression = regression
		comparison.Scenarios = append(comparison.Scenarios, change)
	}
	sort.Slice(comparison.Scenarios, func(i, j int) bool {
		return comparison.Scenarios[i].ID < comparison.Scenarios[j].ID
	})
	return comparison
}
