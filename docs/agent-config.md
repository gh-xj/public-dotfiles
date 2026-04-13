# Agent Config Baseline

`public-dotfiles` owns the reusable, publishable agent baseline for Claude and
Codex.

## Public paths

- `~/.claude/CLAUDE.md`
- `~/.claude/settings.json`
- `~/.claude/hooks/`
- `~/.claude/statusline-command.sh`
- `~/.codex/AGENTS.md`
- `~/.codex/config.toml`
- `~/.codex/rules/default.rules`

## What stays private

Keep these in `private-config` or as live runtime state:

- `~/.claude/settings.local.json`
- `~/.claude/plugins/`
- `~/.claude/skills/`
- `~/.codex/skills/`
- `~/.codex/superpowers/`
- `~/.codex/auth.json`
- per-project trust lists
- custom provider endpoints
- sessions, history, caches, logs, and telemetry

## Intent

The public repo should expose stable behavior and baseline ergonomics, not
account-specific state. If a setting names a private endpoint, hard-codes a
personal workspace list, or depends on local auth material, it does not belong
here.
