package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

func readProbeResults(path string) ([]ProbeResult, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	var results []ProbeResult
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		var probe ProbeResult
		if err := json.Unmarshal(scanner.Bytes(), &probe); err != nil {
			return nil, fmt.Errorf("parse probe sample %d: %w", len(results)+1, err)
		}
		if probe.SchemaVersion != probeSchemaVersion {
			return nil, fmt.Errorf("probe sample %d has unsupported schema_version %d", len(results)+1, probe.SchemaVersion)
		}
		results = append(results, probe)
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	if len(results) == 0 {
		return nil, fmt.Errorf("probe output has no samples")
	}
	return results, nil
}

func resultPath(requested, runID string) (string, error) {
	if requested != "" {
		path, err := filepath.Abs(requested)
		if err != nil {
			return "", err
		}
		return path, nil
	}
	state := os.Getenv("XDG_STATE_HOME")
	if state == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		state = filepath.Join(home, ".local", "state")
	}
	return filepath.Join(state, "nvim-bench", "runs", runID+".json"), nil
}

func printRunSummary(run RunResult) {
	fmt.Printf("%-22s %-8s %10s %10s %10s %8s\n", "scenario", "status", "median", "p95", "process", "plugins")
	for _, result := range run.Scenarios {
		processMedian := 0.0
		if result.ProcessTiming != nil {
			processMedian = result.ProcessTiming.MedianMS
		}
		fmt.Printf("%-22s %-8s %8.1fms %8.1fms %8.1fms %8d\n",
			result.ID, result.Status, result.MedianMS, result.P95MS, processMedian, len(result.LoadedPlugins))
		if result.Error != "" {
			fmt.Printf("  %s\n", result.Error)
		}
	}
}

func secondsToMilliseconds(values []float64) []float64 {
	result := make([]float64, len(values))
	for i, value := range values {
		result[i] = value * 1000
	}
	return result
}

func percentile(values []float64, p float64) float64 {
	if len(values) == 0 {
		return 0
	}
	sorted := append([]float64(nil), values...)
	sort.Float64s(sorted)
	if len(sorted) == 1 {
		return sorted[0]
	}
	position := p * float64(len(sorted)-1)
	lower := int(math.Floor(position))
	upper := int(math.Ceil(position))
	if lower == upper {
		return sorted[lower]
	}
	weight := position - float64(lower)
	return sorted[lower]*(1-weight) + sorted[upper]*weight
}

func summarizeSamples(values []float64) TimingStats {
	stats := TimingStats{SamplesMS: append([]float64(nil), values...)}
	if len(values) == 0 {
		return stats
	}
	stats.MinMS = values[0]
	stats.MaxMS = values[0]
	for _, value := range values {
		stats.MeanMS += value
		stats.MinMS = math.Min(stats.MinMS, value)
		stats.MaxMS = math.Max(stats.MaxMS, value)
	}
	stats.MeanMS /= float64(len(values))
	for _, value := range values {
		delta := value - stats.MeanMS
		stats.StddevMS += delta * delta
	}
	stats.StddevMS = math.Sqrt(stats.StddevMS / float64(len(values)))
	stats.MedianMS = percentile(values, 0.50)
	stats.P95MS = percentile(values, 0.95)
	return stats
}

func commandOutput(name string, args ...string) (string, error) {
	return commandOutputIn("", name, args...)
}

func commandOutputIn(dir, name string, args ...string) (string, error) {
	command := exec.Command(name, args...)
	command.Dir = dir
	output, err := command.Output()
	return string(output), err
}

func shellCommand(env []string, executable string, args []string) string {
	parts := make([]string, 0, len(env)+len(args)+2)
	parts = append(parts, "env")
	for _, value := range env {
		parts = append(parts, shellQuote(value))
	}
	parts = append(parts, shellQuote(executable))
	for _, arg := range args {
		parts = append(parts, shellQuote(arg))
	}
	return strings.Join(parts, " ")
}

func shellQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "'\"'\"'") + "'"
}

func writeJSON(output *os.File, value any) error {
	encoder := json.NewEncoder(output)
	encoder.SetIndent("", "  ")
	return encoder.Encode(value)
}

func writeJSONFile(path string, value any) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	temp := path + ".tmp"
	file, err := os.Create(temp)
	if err != nil {
		return err
	}
	encodeErr := writeJSON(file, value)
	closeErr := file.Close()
	if encodeErr != nil {
		return encodeErr
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(temp, path)
}
