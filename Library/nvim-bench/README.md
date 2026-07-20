# nvim-bench

`nvim-bench` is the versioned benchmark harness for this repository's Neovim
configuration. It measures event readiness rather than treating process startup
as a proxy for every interaction.

## Contract

- `scenarios.json` owns scenario definitions, fixtures, probes, expected LSP
  clients, and budgets.
- `harness.lua` runs before the user config and records `VimEnter` or LSP-ready
  state, including loaded plugins and attached clients. An `lsp_ready` probe
  succeeds only when its declared `expected_client` is initialized.
- The Go CLI owns environment fingerprinting, repeated measurement through
  `hyperfine`, result persistence, and comparisons.
- Scenario median/p95 values come from harness event timestamps. Hyperfine
  wall-clock samples remain available as `process_timing` diagnostics and do
  not drive readiness budgets or comparisons.
- Runs default to the repository's `.config` source so an iteration measures
  the working-tree candidate. Pass `--config-home ~/.config` to measure the
  currently activated Home Manager generation instead.
- Raw results default to `~/.local/state/nvim-bench/runs/`; they are
  machine-local evidence and are not committed.
- Result and manifest schemas are versioned independently of CLI releases.

## Commands

```sh
task nvim-bench:doctor
task nvim-bench:list
task nvim-bench:run -- --suite startup
task nvim-bench:run -- --suite readiness
task nvim-bench:compare -- before.json after.json
```

`compare` reports a regression only when both the relative and absolute gates
are exceeded. Defaults are 10 percent and 5 milliseconds.

Scenario budgets are always recorded. They become an exit-code gate only when
`run --enforce-budgets` is passed; repository smoke checks intentionally test
harness correctness without turning ambient machine noise into config failure.

## Suites

| Suite | Purpose |
| --- | --- |
| `smoke` | Cheap harness verification used by repository checks |
| `startup` | Core, empty config, and representative file-open readiness |
| `readiness` | Language-server correctness and activation latency |
| `scaling` | Deterministic large-file behavior with a `-u NONE` core control |
| `baseline` | All current scenarios |

Add a scenario only when it represents a user workflow or a known risk. Do not
add plugin-specific microbenchmarks unless they explain a measured workflow
regression.
