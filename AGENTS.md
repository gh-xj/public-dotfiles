# Agent Rules

## Scope

This public repo owns reusable macOS app, shell, editor, terminal, CLI, and
agent defaults. It must remain independently usable without `private-config`.
Never add secrets, account/company identifiers, private hosts/IPs, emails, or
user-specific absolute paths; private and machine-local state belongs elsewhere.

## Invariants

- Standalone Home Manager is the only activation path; never add nix-darwin.
- Nix owns shell tools, Brewfile owns native apps, and mise owns runtimes.
- Edit repo sources, never generated files or live home symlinks.
- Preserve mutable agent settings and app-owned out-of-store files.
- Keep the task surface exactly: check, plan, apply, rollback, doctor, capture, apps.

## Commands

- `task check` — pure repo/generation gate; no live home, network, or activation.
- `task plan` — build and preview without activation.
- `task doctor` — read-only live drift and command-provider report.
- `task apply` — Home Manager plus user-level macOS settings; no sudo.
- `task rollback` — activate the previous Home Manager generation.
- `task capture` — capture declared macOS settings into the repo.
- `task apps` — Brewfile plus locked mise tools; human-approved because it may prompt.

## Authority and Done

Use the `config-manager` skill. Preserve unrelated changes and treat public and
private as separate repos. Only the lead session commits on `main`; other agents
use `agent/*` worktrees. Stage explicit paths, inspect `git diff --cached`, and
make imperative atomic commits. Never amend, rebase, reset, force-push, or push
without explicit direction. Work is done only when `task check` passes, the
relevant plan/doctor proof is recorded, and accepted changes are committed.

## Pointers

See `docs/daily-git-workflow.md`, `docs/config-delivery-model.md`, and
`docs/dotfiles-operations.md`. Keep `CLAUDE.md` as the one-line `@AGENTS.md` shim.
