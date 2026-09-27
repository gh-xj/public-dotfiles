package main

import (
	"strings"
	"testing"
)

func float64Ptr(value float64) *float64 { return &value }

func passedProbe(elapsed float64, wall, awake *float64) ProbeResult {
	return ProbeResult{SchemaVersion: probeSchemaVersion, Status: "passed", ElapsedMS: elapsed, WallElapsedMS: wall, AwakeElapsedMS: awake}
}

func TestClassifySampleFlagsClockSkew(t *testing.T) {
	probe := passedProbe(1500, float64Ptr(1500), float64Ptr(100))
	invalid, ok := classifySample(2, probe, 1.6, defaultMaxClockSkewMS)
	if ok {
		t.Fatal("sample spanning a 1.4 s suspend was accepted")
	}
	if invalid.Reason != "clock_skew" || invalid.Index != 2 || invalid.SkewMS != 1400 {
		t.Fatalf("unexpected classification: %#v", invalid)
	}
}

func TestClassifySampleFallsBackToElapsedWithoutAwakeClock(t *testing.T) {
	probe := passedProbe(100, float64Ptr(1500), nil)
	if _, ok := classifySample(0, probe, 0, defaultMaxClockSkewMS); ok {
		t.Fatal("wall/hrtime skew was ignored when the awake clock is missing")
	}
}

func TestClassifySampleAcceptsSmallSkew(t *testing.T) {
	probe := passedProbe(100, float64Ptr(100.4), float64Ptr(100.1))
	if invalid, ok := classifySample(0, probe, 103, defaultMaxClockSkewMS); !ok {
		t.Fatalf("normal sample rejected: %#v", invalid)
	}
}

func TestClassifySampleAcceptsProbeWithoutClockFields(t *testing.T) {
	if _, ok := classifySample(0, passedProbe(100, nil, nil), 0, defaultMaxClockSkewMS); !ok {
		t.Fatal("sample without clock fields was rejected")
	}
}

func TestClassifySampleFlagsProcessDivergence(t *testing.T) {
	// hrtime and wall both absorbed a suspend, the awake clock is missing, but
	// hyperfine's sleep-pausing clock only saw 300 ms of process time.
	probe := passedProbe(2000, float64Ptr(2000), nil)
	invalid, ok := classifySample(1, probe, 300, defaultMaxClockSkewMS)
	if ok || invalid.Reason != "process_divergence" || invalid.SkewMS != 1700 {
		t.Fatalf("unexpected classification: ok=%v %#v", ok, invalid)
	}
}

func TestAggregateSamplesExcludesInvalidFromBothAggregates(t *testing.T) {
	measured := []ProbeResult{
		passedProbe(10, float64Ptr(10.1), float64Ptr(10)),
		passedProbe(3010, float64Ptr(3010), float64Ptr(12)),
		passedProbe(12, float64Ptr(12.1), float64Ptr(12)),
		passedProbe(14, float64Ptr(14.1), float64Ptr(14)),
	}
	processSeconds := []float64{0.020, 3.020, 0.022, 0.024}

	aggregate, err := aggregateSamples(measured, processSeconds, defaultMaxClockSkewMS)
	if err != nil {
		t.Fatal(err)
	}
	if len(aggregate.Invalid) != 1 || aggregate.Invalid[0].Index != 1 {
		t.Fatalf("unexpected invalid samples: %#v", aggregate.Invalid)
	}
	if got := aggregate.Activation.SamplesMS; len(got) != 3 || aggregate.Activation.MaxMS != 14 {
		t.Fatalf("activation aggregate still contains the suspended sample: %#v", aggregate.Activation)
	}
	if got := aggregate.Process.SamplesMS; len(got) != 3 || aggregate.Process.MaxMS != 24 {
		t.Fatalf("process aggregate still contains the suspended sample: %#v", aggregate.Process)
	}
}

func TestAggregateSamplesFailsWhenNoValidSampleRemains(t *testing.T) {
	measured := []ProbeResult{passedProbe(5000, float64Ptr(5000), float64Ptr(10))}
	aggregate, err := aggregateSamples(measured, []float64{5}, defaultMaxClockSkewMS)
	if err == nil || !strings.Contains(err.Error(), "all 1 samples") {
		t.Fatalf("expected all-invalid error, got %v", err)
	}
	if len(aggregate.Invalid) != 1 {
		t.Fatalf("invalid samples were not returned alongside the error: %#v", aggregate)
	}
}

func TestAggregateSamplesRejectsTimingCountMismatch(t *testing.T) {
	measured := []ProbeResult{passedProbe(5, nil, nil), passedProbe(6, nil, nil)}
	if _, err := aggregateSamples(measured, []float64{0.005}, defaultMaxClockSkewMS); err == nil {
		t.Fatal("mismatched hyperfine timing count was accepted")
	}
}

func TestAggregateSamplesReportsFailedProbe(t *testing.T) {
	measured := []ProbeResult{{Status: "failed", Error: "LSP client \"lua_ls\" was not initialized after 3000 ms"}}
	if _, err := aggregateSamples(measured, []float64{1}, defaultMaxClockSkewMS); err == nil || !strings.Contains(err.Error(), "lua_ls") {
		t.Fatalf("failed probe error was not propagated: %v", err)
	}
}
