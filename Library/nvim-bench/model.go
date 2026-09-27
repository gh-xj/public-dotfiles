package main

import "time"

const (
	manifestSchemaVersion = 3
	resultSchemaVersion   = 4
	probeSchemaVersion    = 3
)

type Manifest struct {
	SchemaVersion int        `json:"schema_version"`
	Harness       string     `json:"harness"`
	Scenarios     []Scenario `json:"scenarios"`
}

type Scenario struct {
	ID                string            `json:"id"`
	Description       string            `json:"description"`
	Suites            []string          `json:"suites"`
	Probe             string            `json:"probe"`
	ExpectedClient    string            `json:"expected_client,omitempty"`
	ClientScope       string            `json:"client_scope,omitempty"`
	ExpectedNamespace string            `json:"expected_namespace,omitempty"`
	Fixture           string            `json:"fixture,omitempty"`
	Generate          *GeneratedFixture `json:"generate,omitempty"`
	NvimArgs          []string          `json:"nvim_args,omitempty"`
	TimeoutMS         int               `json:"timeout_ms"`
	BudgetMS          float64           `json:"budget_ms,omitempty"`
}

type GeneratedFixture struct {
	Extension string `json:"extension"`
	Lines     int    `json:"lines"`
	Content   string `json:"content"`
}

type Environment struct {
	OS               string `json:"os"`
	Arch             string `json:"arch"`
	OSVersion        string `json:"os_version,omitempty"`
	CPU              string `json:"cpu,omitempty"`
	NvimRequested    string `json:"nvim_requested"`
	NvimPath         string `json:"nvim_path"`
	NvimResolvedPath string `json:"nvim_resolved_path,omitempty"`
	NvimVersion      string `json:"nvim_version"`
	HyperfinePath    string `json:"hyperfine_path"`
	HyperfineVersion string `json:"hyperfine_version"`
	ConfigHome       string `json:"config_home,omitempty"`
	ConfigPath       string `json:"config_path,omitempty"`
	GitCommit        string `json:"git_commit,omitempty"`
	GitDirty         bool   `json:"git_dirty"`
	ConfigSHA256     string `json:"config_sha256,omitempty"`
	LazyLockSHA256   string `json:"lazy_lock_sha256,omitempty"`
	ManifestSHA256   string `json:"manifest_sha256"`
	HarnessSHA256    string `json:"harness_sha256"`
	// LSPExecutables identifies every external language server binary the
	// run launched; see fingerprint.go.
	LSPExecutables []ExecutableFingerprint `json:"lsp_executables,omitempty"`
}

// ExecutableFingerprint is the recorded identity of one external executable.
type ExecutableFingerprint struct {
	Client       string `json:"client"`
	Command      string `json:"command"`
	Path         string `json:"path"`
	ResolvedPath string `json:"resolved_path,omitempty"`
	SizeBytes    int64  `json:"size_bytes,omitempty"`
	ModTime      string `json:"mtime,omitempty"`
	SHA256Prefix string `json:"sha256_prefix,omitempty"`
	Version      string `json:"version,omitempty"`
	Error        string `json:"error,omitempty"`
}

type RunResult struct {
	SchemaVersion int       `json:"schema_version"`
	RunID         string    `json:"run_id"`
	CreatedAt     time.Time `json:"created_at"`
	Suite         string    `json:"suite"`
	Runs          int       `json:"runs"`
	Warmup        int       `json:"warmup"`
	// MaxClockSkewMS is the per-sample skew threshold used to reject samples
	// that spanned system sleep; see samples.go.
	MaxClockSkewMS float64          `json:"max_clock_skew_ms"`
	Environment    Environment      `json:"environment"`
	Scenarios      []ScenarioResult `json:"scenarios"`
}

type ScenarioResult struct {
	ID                string    `json:"id"`
	Description       string    `json:"description"`
	Probe             string    `json:"probe"`
	ExpectedClient    string    `json:"expected_client,omitempty"`
	ClientScope       string    `json:"client_scope,omitempty"`
	ExpectedNamespace string    `json:"expected_namespace,omitempty"`
	Status            string    `json:"status"`
	Error             string    `json:"error,omitempty"`
	BudgetMS          float64   `json:"budget_ms,omitempty"`
	BudgetPassed      *bool     `json:"budget_passed,omitempty"`
	MeanMS            float64   `json:"mean_ms,omitempty"`
	MedianMS          float64   `json:"median_ms,omitempty"`
	P95MS             float64   `json:"p95_ms,omitempty"`
	StddevMS          float64   `json:"stddev_ms,omitempty"`
	MinMS             float64   `json:"min_ms,omitempty"`
	MaxMS             float64   `json:"max_ms,omitempty"`
	SamplesMS         []float64 `json:"samples_ms,omitempty"`
	// InvalidSampleCount counts measured runs excluded from every aggregate
	// because they spanned system sleep or diverged from process timing.
	InvalidSampleCount int             `json:"invalid_sample_count"`
	InvalidSamples     []InvalidSample `json:"invalid_samples,omitempty"`
	ProcessTiming      *TimingStats    `json:"process_timing,omitempty"`
	LoadedPlugins      []string        `json:"loaded_plugins,omitempty"`
	Clients            []ProbeClient   `json:"clients,omitempty"`
}

type TimingStats struct {
	MeanMS    float64   `json:"mean_ms"`
	MedianMS  float64   `json:"median_ms"`
	P95MS     float64   `json:"p95_ms"`
	StddevMS  float64   `json:"stddev_ms"`
	MinMS     float64   `json:"min_ms"`
	MaxMS     float64   `json:"max_ms"`
	SamplesMS []float64 `json:"samples_ms"`
}

// InvalidSample records one measured run excluded from the aggregates.
type InvalidSample struct {
	Index          int     `json:"index"`
	Reason         string  `json:"reason"`
	ElapsedMS      float64 `json:"elapsed_ms"`
	WallElapsedMS  float64 `json:"wall_elapsed_ms,omitempty"`
	AwakeElapsedMS float64 `json:"awake_elapsed_ms,omitempty"`
	ProcessMS      float64 `json:"process_ms,omitempty"`
	SkewMS         float64 `json:"skew_ms"`
}

type ProbeResult struct {
	SchemaVersion     int           `json:"schema_version"`
	Probe             string        `json:"probe"`
	ExpectedClient    string        `json:"expected_client,omitempty"`
	ClientScope       string        `json:"client_scope,omitempty"`
	ExpectedNamespace string        `json:"expected_namespace,omitempty"`
	Status            string        `json:"status"`
	Error             string        `json:"error,omitempty"`
	ElapsedMS         float64       `json:"elapsed_ms"`
	WallElapsedMS     *float64      `json:"wall_elapsed_ms,omitempty"`
	AwakeElapsedMS    *float64      `json:"awake_elapsed_ms,omitempty"`
	LoadedPlugins     []string      `json:"loaded_plugins,omitempty"`
	Clients           []ProbeClient `json:"clients,omitempty"`
}

type ProbeClient struct {
	Name        string   `json:"name"`
	Initialized bool     `json:"initialized"`
	Cmd         []string `json:"cmd,omitempty"`
	CmdPath     string   `json:"cmd_path,omitempty"`
}

type HyperfineOutput struct {
	Results []HyperfineResult `json:"results"`
}

type HyperfineResult struct {
	Mean   float64   `json:"mean"`
	Stddev float64   `json:"stddev"`
	Min    float64   `json:"min"`
	Max    float64   `json:"max"`
	Times  []float64 `json:"times"`
}

type Comparison struct {
	SchemaVersion int              `json:"schema_version"`
	BeforeRunID   string           `json:"before_run_id"`
	AfterRunID    string           `json:"after_run_id"`
	PercentGate   float64          `json:"percent_gate"`
	AbsoluteGate  float64          `json:"absolute_ms_gate"`
	Regressions   int              `json:"regressions"`
	Scenarios     []ScenarioChange `json:"scenarios"`
}

type ScenarioChange struct {
	ID           string  `json:"id"`
	BeforeStatus string  `json:"before_status"`
	AfterStatus  string  `json:"after_status"`
	BeforeMS     float64 `json:"before_ms"`
	AfterMS      float64 `json:"after_ms"`
	DeltaMS      float64 `json:"delta_ms"`
	DeltaPct     float64 `json:"delta_percent"`
	Regression   bool    `json:"regression"`
	Reason       string  `json:"reason,omitempty"`
}
