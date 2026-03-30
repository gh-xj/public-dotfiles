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

Run:

```bash
./install.sh
```

By default the installer creates symlinks into `$HOME`. Use `--copy` to copy
files instead, or `--dry-run` to preview actions.

Direct repo-local install remains supported. For daily operator workflows,
`machine-control` is the preferred single entrypoint, but it orchestrates this
repo rather than owning its contents.
