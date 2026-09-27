package main

import (
	"errors"
	"fmt"
)

// defaultMaxClockSkewMS is the per-sample clock skew above which a measured
// run is treated as having spanned a host suspend.
const defaultMaxClockSkewMS = 250

// Sample validity and system sleep.
//
// A benchmark sample is the harness-reported activation time of one Neovim
// process. If the host suspends (lid close, idle sleep) while that process is
// running, the sample silently absorbs the suspend and a single run can drag a
// scenario's p95 by seconds while every other sample looks normal. Querying the
// system sleep log (`pmset -g log`, `log show`) is slow, so the harness instead
// records three elapsed clocks per sample and the Go side cross-checks them:
//
//   - elapsed_ms: uv.hrtime(). This is the measurement itself. On macOS libuv
//     backs it with mach_continuous_time, which keeps counting through sleep.
//   - wall_elapsed_ms: gettimeofday(). Always counts sleep.
//   - awake_elapsed_ms: CLOCK_UPTIME_RAW read through LuaJIT FFI on macOS. It
//     stops during sleep. It is absent when FFI is unavailable; the check then
//     falls back to elapsed_ms, which only detects sleep on platforms whose
//     hrtime pauses (Linux CLOCK_MONOTONIC).
//
// wall minus awake is the time the host spent asleep inside the sample. Skew
// above the threshold marks the sample invalid with reason "clock_skew".
//
// As an independent second signal, harness activation time can never
// legitimately exceed hyperfine's wall-clock time for the same process: the
// harness starts after exec and writes its sample before exit. hyperfine
// measures with a clock that pauses during sleep, so activation exceeding the
// process time by more than the threshold marks the sample invalid with reason
// "process_divergence". This catches a suspend even when the awake clock is
// missing.
//
// Invalid samples are dropped from both the activation and process aggregates
// and surfaced as a count plus per-sample detail, so a run never emits a p95
// that quietly includes a suspend. The default threshold is generous because
// the clocks are read microseconds apart and hyperfine subtracts a measured
// shell-spawn overhead from its times; real suspends are seconds or longer.

// sampleAggregate is the validated outcome of one scenario's measured runs.
type sampleAggregate struct {
	Activation TimingStats
	Process    TimingStats
	Invalid    []InvalidSample
}

// classifySample reports whether one measured run is usable. index is the
// zero-based measured-run index, processMS is hyperfine's wall-clock time for
// the same run (0 when unknown).
func classifySample(index int, probe ProbeResult, processMS, maxSkewMS float64) (InvalidSample, bool) {
	sample := InvalidSample{Index: index, ElapsedMS: probe.ElapsedMS, ProcessMS: processMS}
	if probe.WallElapsedMS != nil {
		sample.WallElapsedMS = *probe.WallElapsedMS
		awake := probe.ElapsedMS
		if probe.AwakeElapsedMS != nil {
			awake = *probe.AwakeElapsedMS
			sample.AwakeElapsedMS = awake
		}
		if skew := *probe.WallElapsedMS - awake; skew > maxSkewMS {
			sample.Reason = "clock_skew"
			sample.SkewMS = skew
			return sample, false
		}
	}
	if processMS > 0 {
		if skew := probe.ElapsedMS - processMS; skew > maxSkewMS {
			sample.Reason = "process_divergence"
			sample.SkewMS = skew
			return sample, false
		}
	}
	return InvalidSample{}, true
}

// aggregateSamples validates the measured probes against hyperfine's per-run
// times, excludes invalid samples, and summarizes the rest. The returned
// aggregate carries the invalid samples even when an error is returned.
func aggregateSamples(measured []ProbeResult, processSeconds []float64, maxSkewMS float64) (sampleAggregate, error) {
	var aggregate sampleAggregate
	if len(processSeconds) != len(measured) {
		return aggregate, fmt.Errorf("hyperfine reported %d timings for %d probe samples", len(processSeconds), len(measured))
	}
	processMS := secondsToMilliseconds(processSeconds)
	activation := make([]float64, 0, len(measured))
	process := make([]float64, 0, len(measured))
	for i, probe := range measured {
		if probe.Status != "passed" {
			if probe.Error != "" {
				return aggregate, errors.New(probe.Error)
			}
			return aggregate, fmt.Errorf("probe sample %d failed without an error message", i+1)
		}
		if invalid, ok := classifySample(i, probe, processMS[i], maxSkewMS); !ok {
			aggregate.Invalid = append(aggregate.Invalid, invalid)
			continue
		}
		activation = append(activation, probe.ElapsedMS)
		process = append(process, processMS[i])
	}
	if len(activation) == 0 {
		return aggregate, fmt.Errorf("all %d samples spanned system sleep or exceeded %.0f ms clock skew; rerun the suite",
			len(measured), maxSkewMS)
	}
	aggregate.Activation = summarizeSamples(activation)
	aggregate.Process = summarizeSamples(process)
	return aggregate, nil
}
