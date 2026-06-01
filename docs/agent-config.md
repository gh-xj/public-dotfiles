# Agent Config Baseline

`public-dotfiles` owns the reusable, publishable agent baseline for Claude and
Codex.

## Public paths

Live paths owned by Home Manager:

- `~/.claude/CLAUDE.md`
- `~/.claude/settings.json`
- `~/.claude/hooks/`
- `~/.claude/statusline-command.sh`
- `~/.codex/AGENTS.md`
- `~/.codex/rules/default.rules`

Template path owned by the public repo:

- `.codex/config.toml`

The public Codex template stores reusable baseline settings such as model,
theme, and feature defaults. Bootstrap copies it to `~/.codex/config.toml` only
when that live file is missing or still points at an old read-only public Home
Manager generation. Home Manager must not own the live Codex config because
Codex writes project trust and other runtime state there.

Project-local public skills may live in this repo when they operate this repo
itself. The canonical source for those skills is `.claude/skills/`, with
`.agents/skills/` reserved for Codex discovery adapters when needed. These are
not global home skill trees and are not linked into `~/.claude/skills` or
`~/.codex/skills` by the public Home Manager module.

## What stays private

Keep these in `private-config` or as live runtime state:

- `~/.claude/settings.local.json`
- `~/.claude/plugins/`
- `~/.claude/skills/`
- `~/.codex/skills/`
- `~/.codex/superpowers/`
- `~/.codex/auth.json`
- mutable `~/.codex/config.toml` runtime sections
- per-project trust lists
- custom provider endpoints
- sessions, history, caches, logs, and telemetry

## Intent

The public repo should expose stable behavior and baseline ergonomics, not
account-specific state. If a setting names a private endpoint, hard-codes a
personal workspace list, or depends on local auth material, it does not belong
here.

## Bootstrap Sequence

Build the public Home Manager example without applying it:

```bash
nix build .#homeConfigurations.example.activationPackage
```

To apply the public baseline directly, clone the repo, edit
`hosts/example.nix` for the target macOS account, then run:

```bash
task install
```

For private machines, `private-config` imports this public baseline and adds
only private overlay state:

- `~/.claude/settings.local.json`
- plugins, skills, auth, trust lists, mutable Codex config sections, and
  provider overrides

## Verification

Run this gate after changing Codex config policy:

```bash
task verify:codex-runtime-boundary
```

On a live machine, include the runtime writability check:

```bash
./scripts/verify-codex-runtime-boundary.sh --live
```
