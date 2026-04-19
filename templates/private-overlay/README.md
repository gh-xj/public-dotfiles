# private-config

Local-only private overlay for machines that should keep the split
`public-dotfiles` + `private-config` architecture without syncing the real
private repo.

## Intent

- keep private and machine-local files out of `public-dotfiles`
- track them with local git on this machine
- preserve the same install contract as the main setup

This repo is intentionally local-only. Do not add a remote unless you mean to.

## Workflow

1. Add or edit private files inside this repo.
2. List owned live paths in `private-paths.txt`.
3. Track changes with local git.
4. Run `task install` from `public-dotfiles` to apply the overlay.

The installer only touches paths listed in `private-paths.txt`. Missing source
files are skipped so you can grow the overlay incrementally.
