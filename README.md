# public-dotfiles

Public macOS dotfiles and editor or shell configuration with a direct `$HOME`
layout.

## Ownership

This repo is one live owner for its paths.

- each live path has exactly one owner
- `public-dotfiles` owns the public reusable baseline
- `private-config` owns private durable state
- the active architecture is `public-dotfiles` plus `private-config`

## Scope

This repo keeps only reusable and publishable configuration:

- shell and terminal config
- editor config
- CLI tool config
- window manager and desktop preferences
- public-safe Claude/Codex policy and baseline settings

Private agent runtime state, credentials, custom provider endpoints,
project-trust lists, marketplace state, and personal archives belong in
`private-config`, not here.

## Install

Preferred daily entrypoint:

```bash
task -d ../private-config install:public
```

Repo-local install remains supported when you want to work directly in this
checkout:

```bash
./install.sh
```

By default the installer creates symlinks into `$HOME`. Use `--copy` to copy
files instead, or `--dry-run` to preview actions.

## Agent Baseline

This repo now publishes the reusable Claude/Codex baseline:

- `~/.claude/CLAUDE.md`
- `~/.claude/settings.json`
- `~/.claude/hooks/`
- `~/.claude/statusline-command.sh`
- `~/.codex/AGENTS.md`
- `~/.codex/config.toml`
- `~/.codex/rules/default.rules`

The private repo continues to own agent runtime and account-local material such
as `settings.local.json`, plugin registry state, skills trees, sessions, auth,
and per-project trust or provider overrides. A short reference lives in
`docs/agent-config.md`.

## Onboarding notes

The public repo should be enough for a clean new-machine baseline.

- run `./install.sh`
- the installer links tracked config into `$HOME`

tmux uses an inline One Dark theme with no external plugins required.
If tmux still reports Catppuccin errors on a machine, it has stale host-local
state from an older install.

Recommended cleanup on a new machine:

```bash
tmux kill-server 2>/dev/null || true
rm -f ~/.tmux-catppuccin-theme-sync.sh
```

Then inspect `~/.tmux.local.conf` and remove any legacy Catppuccin references
unless you intentionally want a host-local override.
