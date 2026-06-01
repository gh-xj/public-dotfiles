---
name: public-dotfiles-bootstrap
description: Use when bootstrapping or auditing public-dotfiles on a new Mac, comparing source and target Mac discrepancies, handling public/private config boundaries, or deciding whether macOS, Raycast, display, trackpad, package, or app drift should become repo-owned harness.
---

# Public Dotfiles Bootstrap

Project-local router for restoring and auditing the public, reusable
`public-dotfiles` baseline on a Mac.

## Use This For

- Bootstrapping a new Mac from this repo.
- Comparing source-Mac and target-Mac setup discrepancies.
- Deciding whether macOS, display, Raycast, app, package, input, or terminal
  drift belongs in this repo.
- Strengthening bootstrap scripts, Taskfile gates, or verification harness
  after a discrepancy.

## Do Not Use For

- General app configuration cleanup outside a bootstrap/discrepancy context;
  use `config-manager`.
- Cross-surface persistence proposals; use `harness-router`.
- Generic skill design; use `skill-builder`.
- Sensitive, account-bound, company/private, secret-adjacent, session, cache,
  or credential state; route that to `private-config`.

## First Pass

1. Start with `git status --short --branch`.
2. Read `AGENTS.md`, then the relevant docs:
   - `docs/bootstrap.md`
   - `docs/current-machine-baseline.md`
   - `docs/macos-convergence-model.md`
3. Identify the reported discrepancy and the source/target machines.
4. Inspect before changing:
   - `task inspect:macos-baseline`
   - target equivalent over SSH when available
   - a narrow live-state command for the affected layer
5. Classify the owning layer using `docs/macos-convergence-model.md`.
6. Encode desired public-safe state in repo source, not in live symlinks.
7. Add or strengthen a verifier that fails on the observed drift.
8. Apply narrowly, then run `task dotfiles:verify`.
9. Commit and push according to `AGENTS.md`.

## Layer Heuristics

| Symptom | First Place To Look |
| --- | --- |
| Defaults show correct but behavior differs | live state such as `ioreg`, app cache, GUI session, or TCC |
| Display resolution differs | `config/macos/display-layouts.tsv` and `task verify:display-layout` |
| Tap-to-click or gestures differ | `task input:verify` and live `AppleMultitouchDevice` |
| Raycast command/settings drift | `modules/darwin/defaults.nix`, `config/raycast/script-commands.tsv`, `.config/raycast/scripts`, and Raycast verifiers |
| Store extension missing | `config/raycast/extensions.tsv`; open install intents, do not copy caches |
| Spaces count differs | nonblocking `task verify:spaces`; apply needs Accessibility |
| Package/app drift | Nix package sets, `Brewfile`/Homebrew module, or npm globals ledger |

## Verification

Use the narrowest gate first, then the full gate:

| Change | Narrow Gate |
| --- | --- |
| Bootstrap script or Nix host | `task verify:bootstrap-darwin` |
| Display policy | `task verify:display-layout` |
| Input/trackpad defaults | `task input:verify` |
| Raycast preferences | `task verify:raycast` |
| Raycast script commands | `task verify:raycast-scripts` |
| Raycast runtime/UI setup | `task raycast:runtime-check` |
| Raycast Store extensions | `task verify:raycast-extensions` |
| Spaces | `task verify:spaces` |
| General repo health | `task dotfiles:verify` |

Run `task secrets:staged` before committing scripts, agent config, shell config,
URLs, headers, generated config, or token-adjacent surfaces.

## References

| File | Use For |
| --- | --- |
| `docs/bootstrap.md` | Supported bootstrap entrypoints and phases |
| `docs/current-machine-baseline.md` | Current public-safe desired state |
| `docs/macos-convergence-model.md` | Source-vs-target discrepancy loop and macOS layers |
| `references/trigger-evals.md` | Trigger and non-trigger examples for this skill |

## Gaps

- Source-vs-target baseline diff is still manual; no JSON snapshot comparator
  exists yet.
- Raycast Store extension install, Script Command directory registration,
  command aliases/hotkeys, and Spaces creation remain interactive.
- Trackpad live reload may require sudo GUI-session context or logout/login on
  some target Macs.
