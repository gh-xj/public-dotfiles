package main

type CLI struct {
	Manifest   string `name:"manifest" type:"path" help:"Scenario manifest path; defaults to scenarios.json."`
	JSON       bool   `help:"Emit machine-readable JSON."`
	Verbose    bool   `short:"v" help:"Print runner commands and diagnostics."`
	NoColor    bool   `name:"no-color" help:"Disable colored output."`
	Nvim       string `name:"nvim" help:"Neovim executable path or command name." default:"nvim"`
	ConfigHome string `name:"config-home" type:"path" help:"XDG config home; defaults to the benchmark repository's .config."`

	Doctor  DoctorCmd  `cmd:"" help:"Check benchmark prerequisites and runtime identity."`
	List    ListCmd    `cmd:"" help:"List declared benchmark scenarios."`
	Run     RunCmd     `cmd:"" help:"Run a benchmark suite and persist a versioned result."`
	Compare CompareCmd `cmd:"" help:"Compare two result files and enforce regression thresholds."`
}

type DoctorCmd struct{}

type ListCmd struct {
	Suite string `help:"Only list scenarios in this suite."`
}

type RunCmd struct {
	Suite   string `help:"Scenario suite to run." default:"smoke"`
	Runs    int    `help:"Measured runs per scenario." default:"10"`
	Warmup  int    `help:"Warmup runs per scenario." default:"3"`
	Output  string `name:"output" type:"path" help:"Result JSON path; defaults to the user state directory."`
	Budgets bool   `name:"enforce-budgets" help:"Fail scenarios whose p95 exceeds the declared budget."`
}

type CompareCmd struct {
	Before       string  `arg:"" type:"existingfile" help:"Reference result JSON."`
	After        string  `arg:"" type:"existingfile" help:"Candidate result JSON."`
	Percent      float64 `help:"Relative regression threshold percentage." default:"10"`
	AbsoluteMS   float64 `name:"absolute-ms" help:"Absolute regression threshold in milliseconds." default:"5"`
	AllowFailure bool    `name:"allow-regression" help:"Report regressions without returning an error."`
	Incompatible bool    `name:"allow-incompatible" help:"Compare results with different runtime or manifest identities."`
}
