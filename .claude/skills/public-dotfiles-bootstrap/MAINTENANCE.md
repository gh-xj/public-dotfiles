# Public Dotfiles Bootstrap Skill Maintenance

This is the append-only maintenance log for the project-local bootstrap skill.
Use it when a real bootstrap discrepancy changes the workflow, ownership
boundary, verifier set, or trigger wording.

## When This File Changes

- A target Mac discrepancy produces a new verifier or convergence task.
- A public/private boundary changes during bootstrap.
- A repeated failure mode becomes recognizable enough to route by symptom.
- A regression case is added to keep future agents from reintroducing drift.

## Lessons

### 2026-06-02 - Codex runtime config must stay mutable

**Trigger:** Codex could not persist project trust and showed
`config/batchWrite failed in TUI`.

**Change:** `fe40b49` made `.codex/config.toml` a public template that seeds a
writable live file instead of a Home Manager-owned symlink into the Nix store.

**Expected effect:** Bootstrap can install public Codex defaults while Codex can
still write trust, plugins, and other runtime state.

**Falsifier:** `task verify:codex-runtime-boundary -- --live` fails, or
`~/.codex/config.toml` points into `/nix/store`.

### 2026-06-02 - Trackpad behavior has persisted and live layers

**Trigger:** Persisted trackpad defaults looked correct but tap-to-click still
felt disabled on the target Mac.

**Change:** `53a1429` added `task input:reload-live`; `45d74c1` allowed
bootstrap to continue after persisted defaults are written even when live state
needs a later reload.

**Expected effect:** Agents diagnose the live device state separately from the
persisted defaults and run convergence before declaring input complete.

**Falsifier:** `task input:verify` passes, but live `AppleMultitouchDevice`
state still reports tap-to-click disabled after `task input:reload-live`.

### 2026-06-02 - Tap-to-click requires the global key too

**Trigger:** CurrentHost trackpad defaults were present, but physical
tap-to-click still did not match the source Mac.

**Change:** `ca9864d` added `NSGlobalDomain com.apple.mouse.tapBehavior = 1` to
the input defaults baseline.

**Expected effect:** A fresh bootstrap writes both global and currentHost
tap-to-click defaults before live convergence.

**Falsifier:** `defaults read NSGlobalDomain com.apple.mouse.tapBehavior` on the
target Mac does not return `1` after apply.

### 2026-06-02 - Selected input source is runtime state

**Trigger:** The selected keyboard/input source changed during real use and
caused false baseline drift.

**Change:** `1404b5c` removed `AppleSelectedInputSources` from the public
baseline and verification path.

**Expected effect:** Bootstrap owns enabled public-safe input sources but does
not fail because the user currently selected a different source.

**Falsifier:** A verifier fails only because the currently selected input source
differs.

### 2026-06-02 - Raycast preferences need an explicit apply task

**Trigger:** Raycast installed successfully but public-safe preferences drifted
on the target Mac.

**Change:** `0fe0a2e` added `task raycast:apply-preferences` and wired it into
post-bootstrap convergence.

**Expected effect:** Agents use the narrow Raycast preference apply path before
editing broader Darwin defaults or copying app caches.

**Falsifier:** `task verify:raycast` fails on a known public-safe preference and
there is no narrow apply command to rerun.

### 2026-06-02 - npm globals are not Homebrew packages

**Trigger:** Bootstrap verification found missing CLI commands that are
distributed through npm, not Homebrew.

**Change:** `c673eab` moved npm-distributed CLIs into the npm global ledger and
bootstrap installer.

**Expected effect:** Missing commands such as `gemini` are fixed by
`./scripts/install-npm-globals.sh` plus `task verify:npm-globals`, not by
expanding the Brewfile.

**Falsifier:** A public npm CLI is required for the baseline but is only listed
in Homebrew sources.

### 2026-06-02 - Post-bootstrap convergence is a first-class phase

**Trigger:** Some app and live-state settings only converged after a successful
package/defaults apply.

**Change:** `03c30c6` added `task dotfiles:converge` for live input reload,
Raycast preference application, npm global installation, and full verification.

**Expected effect:** After bootstrap, agents run convergence on the target Mac
before treating a discrepancy as a new missing baseline.

**Falsifier:** A target Mac is judged incomplete before
`task dotfiles:converge && task dotfiles:verify` has been attempted.

### 2026-06-07 - The public Codex seed template cannot live at `.codex/config.toml`

**Trigger:** Codex started parsing `.codex/config.toml` as project-local config
inside this repo, which produced unsupported-key warnings and unstable-feature
warnings from a file that was only meant to seed `~/.codex/config.toml`.

**Change:** Move the seed template to `config/codex/config.toml`, keep
`.codex/config.toml` absent, and make
`task verify:codex-runtime-boundary` fail if the reserved project-local path is
reintroduced.

**Expected effect:** The public bootstrap still seeds a writable live Codex
config, but opening this repo no longer causes Codex to parse the seed template
as repo-local config.

**Falsifier:** Opening `public-dotfiles` still shows a warning that references
`.codex/config.toml`, or `task verify:codex-runtime-boundary` passes while that
path exists in the repo.

### 2026-06-07 - Bootstrap must align `nix-darwin` with the pinned public `nixpkgs` release

**Trigger:** `task verify:bootstrap-darwin` started failing because generated
bootstrap flakes hard-coded `nix-darwin/master` while the pinned public
`nixpkgs` release still evaluated as `26.05`.

**Change:** `scripts/bootstrap-macos.sh` now derives `nix-darwin-YY.MM` from
the current public `nixpkgs` release when it generates a Darwin bootstrap
flake, and falls back to `master` only when it cannot determine a release.

**Expected effect:** Darwin bootstrap verification stays compatible across
upstream release-branch cutovers without requiring a manual script edit.

**Falsifier:** `task verify:bootstrap-darwin` fails with a
`nix-darwin`/`nixpkgs` release mismatch while the generated bootstrap flake
still points at `master`.

### 2026-06-02 - Worker Mac failures need regression coverage

**Trigger:** An Intel macOS bootstrap surfaced multiple independent installer,
platform, package, and app-preference failures in one run.

**Change:** `03bfba8` added a regression eval covering Intel platform
detection, macOS 13 Nix installer compatibility, Homebrew version gates, npm
CLI ownership, live input reload, and Raycast preference drift.

**Expected effect:** Future edits to the bootstrap skill preserve the
multi-branch diagnostic path instead of collapsing it into one package fix.

**Falsifier:** `references/trigger-evals.md` no longer distinguishes platform,
installer, package source, live input, and app preference failures.
