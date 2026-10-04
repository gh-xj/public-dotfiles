---
scope: public-dotfiles
scope_slug: public-dotfiles
date: 2026-10-04
depth: normal
lenses: [L1, L2, L3, L4, L5]
intake:
  context_constraints: [standalone-home-manager, fixed-seven-tasks, preserve-mutable-state, public-private-separation]
  notes: User authorized parallel discovery, repeated counterevidence and a scoped verified fix.
generated_by: attack-architecture skill
---

# Architecture Attack Report — public-dotfiles

## Executive summary

Baseline: `a0dfe71`. Findings describe that revision unless a resolution is named.
Read-only reviewers explored five lenses, then separate agents traced callers,
challenged failure modes and reproduced selected cases in temporary fixtures.

1. **Mutable ownership is duplicated across lifecycle layers.** L2/L3/L5 converge on the same registry; disabling a feature during legacy-link migration needs an explicit ownership handoff.
2. **Shell startup can diverge from the declared provider order.** macOS `path_helper` and system interactive Nix startup both reorder PATH. Fixed in `6685cc0`; generated-output fixtures cover four shell modes and nested login.
3. **A single provider could have the wrong declared owner.** Fixed in `832bd4a`; mise commands supplied only by another managed owner now fail provenance checks.
4. **Reload failures are not surfaced separately from preference writes.** Confirmed with mocked commands, with the important exception that `killall` may legitimately find no process.
5. **The plan CLI retained an unsupported system scope.** Fixed in `30cdc08`; CLI and internal calls reject it before reading generation/live state.
6. **TOML parsing could print a lazy evaluation error and still exit successfully.** Independent TeamX fixtures reproduced it. Fixed in `af800fc` by forcing JSON evaluation; complete-verifier valid/invalid controls pass.

## Hotspots

| Module | Lenses | Pressure |
| --- | --- | --- |
| `modules/home/control.nix` + `scripts/public-control.py` | L2, L3, L5 | Mutable targets, metadata and enabled-state lifecycle are repeated across producers and consumers. |
| `scripts/provenance.py` | L4, L5 | Unavailable inventory can shrink coverage; executable names and expected ownership need explicit contracts. |

Ranking uses severity weights low=1, med=2, high=3, confidence, and the multiplier
`1 + 0.5 * (distinct lens hits - 1)`. Cross-lens coincidence identifies review
priority; it is not independent proof that every allegation is correct.

## Findings by lens

### L1 — Overengineering

**Unsupported system scope.** Evidence at baseline: `scripts/public-control.py:455`,
`choices=("home", "system")`; line 427 claimed sudo was required. Both known
wrappers passed `home`; history traced the branch to removed nix-darwin support.
Severity med; confidence 99; radius narrow; tags YAGNI, ExplicitDependency.
Why it hurts: the public CLI advertises an activation scope it cannot execute.
Minimal fix: reject system scope; implemented in `30cdc08`. Structural fix: none needed.

**Downstream scratch package has a public-specific API.** Evidence:
`modules/home/composition.nix:20`, `scratchGc.package = lib.mkOption`, and line 31,
`home.file.".local/bin/scratch-gc".source`. Severity low; confidence 65; radius module;
tags YAGNI, Coupling. Why it hurts: a downstream implementation imposes a public
package/binary-name contract. Minimal/structural fix: not expanded; do not remove
without proving that downstream composition guarantees are unnecessary.

### L2 — Data model and contract

**Preservation follows desired feature enablement.** Evidence:
`modules/home/control.nix:4`, `mutableTargets = lib.optionals cfg.agents.policy.enable`,
and `scripts/public-control.py:75`, `if name in skip:`. Severity med; confidence 92;
radius cross-cutting; tags BoundedContext, DesignForFailure. Why it hurts: a legacy
Home Manager link excluded by the new flags can bypass byte preservation before
old-generation cleanup. Already regular mutable files are unaffected.
Minimal fix: add a legacy-public-link-to-disabled transition fixture and define
the handoff. Structural fix: distinguish preserve/release/seed from desired enablement.
Respect explicit downstream ownership; removing all skips is not a safe fix.

**Schema marker lacks a reader contract.** Evidence: `control.nix:17`, `schema = 1`,
while `public-control.py:66` returns parsed metadata without version validation.
Severity low; confidence 98; radius module; tags Observability, ExplicitDependency.
Why it hurts: absent, invalid and incompatible metadata collapse into fallbacks.
Minimal fix: distinguish unsupported metadata when changing the schema. Structural
fix: a versioned reader contract, only when a real second version is introduced.

**Manifest entries are filtered by a second registry.** Evidence:
`public-control.py:268`, `return tuple(name for name in MUTABLE if name in declared)`.
Severity med; confidence 98; radius cross-cutting; tags DRY, Coupling. Why it hurts:
adding a declaration alone does not extend preservation or diagnosis.
Minimal fix: document the closed registry and exercise onboarding omissions.
Structural fix: one explicit ownership registry shared by generation and consumers.

### L3 — Coupling and module boundaries

**Mutable registry spans seed, metadata and migration.** Evidence:
`modules/home/agents/hooks.nix:34`, `sourceRel = "config/codex/hooks.json"`, plus the
L2 whitelist. Severity med; confidence 98; radius cross-cutting; tags DRY, Coupling.
Why it hurts: a new writable agent file requires synchronized changes in multiple
layers. Minimal/structural fixes: see L2; avoid creating another registry.

**Ghostty shortcuts encode the tmux prefix.** Evidence: `terminal.nix:44`,
`prefix = "C-s"`, `.tmux.conf:40`, `set -g prefix C-s`, and injected bytes in
`terminal.nix:86`. Severity med; confidence 99; radius cross-cutting; tags DRY,
Coupling. Why it hurts: changing the prefix requires synchronized cross-app edits.
Minimal fix: a shared declaration or consistency check if prefix customization is supported.
Structural fix: not expanded; first establish the supported customization contract.

**Workmux shim assumes the default profile location.** Evidence:
`config-files.nix:40` executes `$HOME/.local/state/nix/profiles/home-manager/home-path/bin/workmux`,
while `.zshenv` uses `XDG_STATE_HOME`. Severity med; confidence 96; radius module;
tags ExplicitDependency, Coupling. Why it hurts: relocating state can separate
runtime selection from diagnosis. Minimal fix: make the shim honor the same
profile contract. Structural fix: not expanded.

**Workmux helper independently selects a package.** Evidence:
`agents/hooks.nix:8`, `pkgs.callPackage ../../../packages/workmux.nix { }`.
Severity low; confidence 80; radius module; tags Coupling. Why it hurts: downstream
package overrides may not cover the helper's dependency. Minimal fix: verify a
real override consumer before generalizing. Structural fix: not expanded.

### L4 — Silent failures and error handling

**Reload outcomes are discarded.** Evidence: `macos-settings.py:173–175`,
`run(ACTIVATE_SETTINGS, "-u", check=False)` and `killall` with `check=False`.
Severity med after counterevidence; confidence 97; radius module; tags
Observability, DesignForFailure. Why it hurts: written preferences can converge
while running services retain old behavior; a subsequent no-diff apply skips reload.
Minimal fix: expose write/reload results independently and tolerate absent services.
Structural fix: explicit retryable convergence stages. No live reload failure was claimed.

**Unavailable inventory can look empty.** Evidence: `provenance.py:32–33`,
`except OSError: return set()`, and the analogous mise-read fallback.
Severity med; confidence 99; radius module; tags Observability. Why it hurts:
successful diagnosis can cover fewer owners without describing missing evidence.
Minimal fix: report inventory coverage. Structural fix: distinguish empty from unavailable.

**Defaults-read failures look like missing preferences.** Evidence:
`macos-settings.py:35–37`, nonzero export returns `{}`. Severity med; confidence 96;
radius module; tags Observability, DesignForFailure. Why it hurts: missing domains
and failed observations lead to the same write decision. Minimal fix: classify
expected absence separately; structural fix: typed observation results.

**Probe failures collapse into coarse states.** Evidence: `public-control.py:31–32`
maps OSError and timeout to the same result. Severity low; confidence 96; radius
cross-cutting; tags Observability. Why it hurts: diagnosis cannot distinguish
missing tools, timeout or access failures. Privacy-safe output is intentional.
Minimal fix: fixed safe failure categories; structural fix: not expanded.

### L5 — Evolvability

**Mutable-file onboarding needs coordinated edits.** Evidence:
`verify-generated-links.py:49` repeats the mutable tuple in addition to L2/L3.
Severity med; confidence 97; radius cross-cutting; tags DRY, Coupling.
Why it hurts: an omitted verifier or migration entry can silently reduce coverage.
Minimal/structural fixes: see L2.

**Mise packages require a parallel executable-name ledger.** Evidence:
`provenance.py:22`, `"npm:@jackwener/wx-cli": {"wx"}`, and the fallback at line 105.
Severity med; confidence 96; radius module; tags DRY, ExplicitDependency.
Why it hurts: package names do not always imply executable names, and the TOML
parser accepts only a subset of syntax. Minimal fix: explicit onboarding evidence;
structural fix: derive executable inventory from an authoritative installed-tool contract.

**Generic program metadata is Yazi-specific.** Evidence: `control.nix:7`,
`yaziPackage = lib.findFirst`, and `public-control.py:341`, `for name in ("yazi", "ya")`.
Severity low; confidence 94; radius module; tags Coupling. Why it hurts: extending
version checks requires changes in both producer and consumer. Minimal fix:
describe the narrow contract; structural fix only when another real consumer needs it.

## Debate transcripts

Depth was normal; selected counterevidence reviews were added without claiming a
complete five-finding formal debate protocol.

- **Mutable preservation:** attacker traced new flags to `--skip`; defender limited
  the risk to legacy HM links and identified downstream non-detachment guarantees.
  Judge: confirmed, 92; add an ownership-handoff fixture before changing behavior.
- **Reload failure:** attacker reproduced swallowed errors with mocks; defender
  showed no-process `killall` is legitimate. Judge: exaggerated severity, 97;
  separate successful writes from reload outcome.
- **PATH:** generated-output tests exposed both login and interactive startup
  interference. Defender confirmed the second system layer. The final snapshot
  clears inherited export state, preserves downstream overlays, and restores in
  `.zprofile`/`.zshrc` without re-sourcing private environment code.
- **Owner mismatch:** temporary mise declarations plus only Brew providers passed
  the old audit. Independent review found the committed owner mapping and tests sound.

## Ranked mitigation plan

| Priority | Action | Status |
| --- | --- | --- |
| 1 | Reject unsupported system plans | Committed `30cdc08`; targeted fixtures, `task check`, real JSON plan passed. |
| 2 | Detect singleton wrong-owner providers | Committed `832bd4a`; regression fixtures, independent review and `task check` passed. |
| 3 | Restore declared provider order after system startup | Committed `6685cc0`; four shell modes, nested login, single private load, `task check` and real JSON plan passed. |
| 3 | Reject malformed TOML in the native parser gate | Committed `af800fc`; full-verifier positive/negative fixtures and `task check` passed. |
| 4 | Model legacy mutable-state ownership handoff | Confirmed edge case; preserve downstream opt-out contract. |
| 5 | Report write/reload observations separately | Mock proof complete; no actual service restart performed. |
| 6 | Review recovery-test coverage | `test-tmux-recovery.py` remains useful but is outside the pure gate; do not label it dead or add a new task. |

The script-line budget rose from 2450 to 2524 for four focused fixes and
regressions. Task, script-file, canonical budget-counted docs, hook and skill
counts did not increase. This archival report is under `.docs`, outside the
canonical `docs_root` count. No activation was performed; the generated PATH
change requires the owning profile's next activation to reach the live shell.

## What was NOT attacked

- No dedicated security review, credential operations, package removal or activation.
- L6 concurrency and L7 performance were not selected.
- Private machine evidence and work-history analysis are retained in a private work space.
- No production executable was proved dead by the bounded reference inventory.
- `task check` passed on Apple Silicon; it does not prove live-machine convergence
  or Intel execution. Existing upstream Nix evaluation warnings remained.
- Live provenance reported drift; it also retains known limits around system PATH
  precedence and whether an existing mise shim has a usable backend.
- Principle tags identify pressure; concrete source evidence and reproduction determine confidence.

## Handoff

Next useful task: verify the committed shell fix through actual application
entrypoints after the owning profile is activated. Repeat provenance and
dependency review before considering removal of duplicate tools.
