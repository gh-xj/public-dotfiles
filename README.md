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

Canonical bootstrap entrypoint:

```bash
task install
```

`task install` always installs the public baseline from this repo. If a sibling
`../private-config` checkout exists, it installs that private overlay in the
same run. On a machine that only has `public-dotfiles`, the same command still
works and simply skips the private layer.

If you do not have access to the real private repo, scaffold a local-only
overlay repo that keeps the same split architecture:

```bash
task private:init
```

That creates `../private-config` as a local git repo with no remote. Add the
private files you want to track there, then rerun `task install`.

Repo-local script entrypoint:

```bash
./install.sh
```

Pass flags after `--` when needed:

```bash
task install -- --dry-run
task install -- --public-only
task install -- --copy
```

Override the private repo location with an environment variable:

```bash
PRIVATE_REPO_DIR=/path/to/private-config task install
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

- run `task install`
- if you need a machine-local private layer with no remote, run `task private:init`
- if `private-config` is added later, rerun the same command
- if `PRIVATE_REPO_DIR` is set and missing, install fails loudly; if the
  default sibling is missing, install skips the overlay
- the public repo owns the reusable baseline; the private repo is an optional
  overlay for private durable state

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
