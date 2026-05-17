package verify

import (
	"context"
	"testing"

	"configctl/internal/report"
)

func TestRunnerCollectsAllRequiredFailures(t *testing.T) {
	runner := Runner{Checks: []Check{
		{
			ID:       "first",
			Name:     "first",
			Required: true,
			Run: func(context.Context) CheckResult {
				return CheckResult{
					OK:      false,
					Summary: "first failed",
					Diagnostics: []report.Diagnostic{{
						Severity: "error",
						Code:     "first.failed",
						Message:  "first failed",
					}},
				}
			},
		},
		{
			ID:       "second",
			Name:     "second",
			Required: true,
			Run: func(context.Context) CheckResult {
				return CheckResult{
					OK:      false,
					Summary: "second failed",
					Diagnostics: []report.Diagnostic{{
						Severity: "error",
						Code:     "second.failed",
						Message:  "second failed",
					}},
				}
			},
		},
	}}

	result := runner.Run(context.Background(), ProfileDefault)

	if result.OK {
		t.Fatal("expected runner to fail")
	}
	if result.Counts.RequiredFailed != 2 {
		t.Fatalf("required failures = %d, want 2", result.Counts.RequiredFailed)
	}
	if len(result.Diagnostics) != 2 {
		t.Fatalf("diagnostics = %#v, want two failures", result.Diagnostics)
	}
}

func TestRunnerSkipsFullOnlyChecksForDefaultProfile(t *testing.T) {
	called := false
	runner := Runner{Checks: []Check{
		{
			ID:       "full",
			Name:     "full",
			Required: true,
			FullOnly: true,
			Run: func(context.Context) CheckResult {
				called = true
				return CheckResult{OK: true}
			},
		},
	}}

	result := runner.Run(context.Background(), ProfileDefault)

	if called {
		t.Fatal("full-only check should not run for default profile")
	}
	if result.Counts.Total != 0 {
		t.Fatalf("total checks = %d, want 0", result.Counts.Total)
	}
}
