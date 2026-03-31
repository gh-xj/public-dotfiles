# public-dotfiles

Public macOS dotfiles and editor or shell configuration with a direct `$HOME`
layout.

## Ownership

This repo is one live owner for its paths.

- each live path has exactly one owner
- `public-dotfiles` owns the public reusable baseline
- `private-config` owns private durable state
- Mackup is historical only and is not part of the active ownership model
- ownership for these paths stays in this repo, not in `machine-control`

## Scope

This repo keeps only reusable and publishable configuration:

- shell and terminal config
- editor config
- CLI tool config
- window manager and desktop preferences

Private agent state, credentials, account-specific material, and personal
archives belong in `private-config`, not here.

## Install

Preferred daily entrypoint:

```bash
machine-control install:public
```

Repo-local install remains supported when you want to work directly in this
checkout:

```bash
./install.sh
```

By default the installer creates symlinks into `$HOME`. Use `--copy` to copy
files instead, or `--dry-run` to preview actions.

## Onboarding notes

The public repo should be enough for a clean new-machine baseline.

- run `./install.sh`
- the installer links tracked config into `$HOME`
- the installer also bootstraps the tmux `catppuccin/tmux` plugin

tmux shared config no longer depends on the old macOS appearance sync script.
If tmux still reports `tmux-catppuccin-theme-sync.sh` or Catppuccin `127`
errors on a new machine, the usual cause is stale host-local state such as
`~/.tmux.local.conf` or an old tmux server started with previous hooks.

Recommended cleanup on a new machine:

```bash
tmux kill-server 2>/dev/null || true
rm -f ~/.tmux-catppuccin-theme-sync.sh
```

Then inspect `~/.tmux.local.conf` and remove any legacy
`tmux-catppuccin-theme-sync.sh` references unless you intentionally want a
host-local override.
