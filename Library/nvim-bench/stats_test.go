package main

import "testing"

func TestPercentile(t *testing.T) {
	values := []float64{5, 1, 4, 2, 3}
	if got := percentile(values, 0.5); got != 3 {
		t.Fatalf("median = %v, want 3", got)
	}
	if got := percentile(values, 0.95); got != 4.8 {
		t.Fatalf("p95 = %v, want 4.8", got)
	}
}

func TestCompareRunsRequiresBothGates(t *testing.T) {
	before := RunResult{RunID: "before", Scenarios: []ScenarioResult{
		{ID: "small-absolute", Status: "passed", MedianMS: 10},
		{ID: "small-relative", Status: "passed", MedianMS: 100},
		{ID: "regression", Status: "passed", MedianMS: 100},
	}}
	after := RunResult{RunID: "after", Scenarios: []ScenarioResult{
		{ID: "small-absolute", Status: "passed", MedianMS: 12},
		{ID: "small-relative", Status: "passed", MedianMS: 106},
		{ID: "regression", Status: "passed", MedianMS: 116},
	}}

	comparison := compareRuns(before, after, 10, 5)
	if comparison.Regressions != 1 {
		t.Fatalf("regressions = %d, want 1", comparison.Regressions)
	}
}

func TestCompareRunsTreatsFailedCandidateAsRegression(t *testing.T) {
	before := RunResult{RunID: "before", Scenarios: []ScenarioResult{
		{ID: "lsp", Status: "passed", MedianMS: 200},
	}}
	after := RunResult{RunID: "after", Scenarios: []ScenarioResult{
		{ID: "lsp", Status: "failed", Error: "timeout"},
	}}

	comparison := compareRuns(before, after, 10, 5)
	if comparison.Regressions != 1 || !comparison.Scenarios[0].Regression {
		t.Fatalf("failed candidate was not treated as a regression: %#v", comparison)
	}
}

func TestCompatibleRunsRejectsHarnessChanges(t *testing.T) {
	before := RunResult{
		Suite:  "smoke",
		Runs:   10,
		Warmup: 3,
		Environment: Environment{
			HarnessSHA256: "before",
		},
	}
	after := before
	after.Environment.HarnessSHA256 = "after"

	if err := compatibleRuns(before, after); err == nil {
		t.Fatal("compatibleRuns accepted different harness fingerprints")
	}
}
