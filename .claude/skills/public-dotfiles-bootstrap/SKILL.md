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
- Strengthening bootstrap scripts, Taskfile gates, or verification after a
  discrepancy.

## Do Not Use For

- General app configuration cleanup outside a bootstrap/discrepancy context;
  use `config-manager`.
- Cross-surface persistence proposals; use `harness-router`.
- Generic skill design; use `skill-builder`.
- Sensitive, account-bound, company/private, secret-adjacent, session, cache,
  or credential state; route that to the private owner.

## First Pass

1. Start with `git status --short --branch`.
2. Read `AGENTS.md`, `README.md`, and the relevant section of
   `docs/bootstrap.md` or `docs/macos-convergence-model.md`.
3. Identify the discrepancy and the source and target machines.
4. Inspect before changing:
   - compare `defaults read` with `modules/darwin/defaults.nix`
   - inspect the target equivalent over SSH when available
   - use a narrow live-state command for the affected layer
5. Classify the owner with `docs/macos-convergence-model.md`.
6. Encode public-safe desired state in repo source, not live symlinks.
7. Add a verifier only when the declaration or build cannot prove the behavior.
8. Run the narrow non-mutating gate, then `task check`.
9. Apply only when the user requested it, using `docs/bootstrap.md`.
10. Commit according to `AGENTS.md`.

## Layer Heuristics

| Symptom | First Place To Look |
| --- | --- |
| Defaults match but behavior differs | `ioreg`, app cache, GUI session, or TCC |
| Display resolution differs | `config/macos/display-layouts.tsv` and `scripts/apply-display-layout.sh` |
| Tap-to-click or gestures differ | `modules/darwin/defaults.nix`, then live `AppleMultitouchDevice` state |
| Raycast drift | `modules/darwin/defaults.nix`, `.config/raycast/scripts`, and `config/raycast/extensions.tsv` |
| Package/app drift | Nix package sets, `modules/darwin/homebrew.nix`, or `npm-globals.txt` |

## Verification

| Change | Gate |
| --- | --- |
| Bootstrap script or Nix host | `task check` |
| Display policy | inspect `scripts/apply-display-layout.sh`; `task apply` is mutating |
| Raycast Store extensions | `task raycast:install` |
| General repo health | `task check` |

`task check` runs the staged secret scan and public identifier denylist.

## Gaps

- Source-vs-target baseline comparison is manual.
- Raycast Store extension install, Script Command directory registration, and
  aliases/hotkeys remain interactive.
- Trackpad behavior may require a GUI-session reload after apply.
