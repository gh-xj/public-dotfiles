# public-dotfiles

`public-dotfiles` is a public-safe macOS baseline for shell, editor, terminal,
CLI, and agent policy. It can be built directly as a Home Manager example,
or imported by a private flake. Credentials, app sessions, provider endpoints,
project trust lists, and machine-local runtime state stay out of this repo.

## Quick Start

Build the public Home Manager example without touching your home directory:

```bash
nix build github:gh-xj/public-dotfiles#homeConfigurations.example.activationPackage
```

Apply the example only from a matching test account named `example`, or after
cloning and editing `hosts/example.nix` for your own macOS user:

```bash
nix run github:nix-community/home-manager/master -- switch --flake .#example
```

See [docs/bootstrap.md](docs/bootstrap.md) for the full student bootstrap path
and package set selection.

## Ownership

This repo is one live owner for its paths.

- each live path has exactly one owner
- `public-dotfiles` owns the public reusable baseline
- `private-config` owns private durable state
- the active architecture is `public-dotfiles` plus `private-config`

## Repository Names

The Nix migration keeps the current repository names:

- public baseline: `gh-xj/public-dotfiles`
  (`https://github.com/gh-xj/public-dotfiles`)
- private overlay and full-machine control plane: `gh-xj/private-config`
  (`https://github.com/gh-xj/private-config`)

Do not rename these to `dotfiles-public` or `dotfiles-private`; those names are
only conceptual roles in older planning notes.

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

Canonical local Home Manager entrypoint:

```bash
task install
```

`task install` runs Home Manager against the local `.#example` configuration.
Use it only from a clone whose `hosts/example.nix` matches the target macOS
account. xj's real laptop setup imports this repo from `private-config` and is
applied there with `task switch`.

## Nix Package Sets

The public flake exports named package sets:

- `packageSets.shell`
- `packageSets.dev`
- `packageSets.ops`
- `packageSets.teaching`

The default public Home Manager module composes all four for
`homeConfigurations.example`. A host can choose a subset:

```nix
{
  xj.publicDotfiles = {
    enable = true;
    packageSets = [ "shell" "dev" "teaching" ];
  };
}
```

A downstream private flake can import only the sets it wants, or run the same
module against a different nixpkgs pin with
`--override-input nixpkgs <flake-url>`.

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

- build the example with `nix build .#homeConfigurations.example.activationPackage`
- edit `hosts/example.nix` for the target macOS user before applying it
- run `task install` only after the local example host matches that user
- use `private-config` when the machine needs private overlays or secrets
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
