# public-dotfiles

`public-dotfiles` is the public-safe split of xj's macOS configuration. It owns
the non-sensitive shell, editor, terminal, CLI, GUI app, package, and agent
defaults needed to restore a comfortable operating environment. It can be
applied directly with Home Manager or imported by a private flake. Credentials,
app sessions, provider endpoints, project trust lists, company/private settings,
and machine-local runtime state stay out of this repo.

## Quick Start

From a fresh macOS clone, run the stock bootstrap entrypoint first:

```bash
./scripts/bootstrap-macos.sh
```

The default mode is a non-mutating preflight. It checks the machine, generates a
local Home Manager host under `~/.local/state/public-dotfiles/bootstrap/`, and
builds the activation package if Nix is already installed. To apply the public
baseline:

```bash
./scripts/bootstrap-macos.sh --apply
```

To include the macOS system phase that applies the public nix-darwin/Homebrew
app ledger, opt in explicitly:

```bash
./scripts/bootstrap-macos.sh --darwin --apply
```

After the user-level apply, run `task dotfiles:verify-user`. After the Darwin
phase has installed the public GUI/app ledger, run `task dotfiles:verify`.

`--darwin --apply` uses `sudo` for `darwin-rebuild switch`. If Homebrew is
missing from `/opt/homebrew`, it runs the official Homebrew installer first
because nix-darwin's Homebrew module manages Homebrew packages but does not
install Homebrew itself.
When running over SSH, use an interactive session or pre-authorize sudo on the
target machine before invoking the command.

On a stock Mac without Nix, use `--install-nix --apply` if you want the script
to run the official macOS daemon installer before Home Manager. The script also
prints the upstream install commands when Nix is missing.

`--apply` backs up unmanaged files that already exist at Home Manager-owned
paths with a `public-dotfiles-backup-<timestamp>` extension before linking the
public baseline. Use `--no-backup` when you want Home Manager to fail on those
conflicts instead.

You can still build the public Home Manager example without touching your home
directory:

```bash
NIX_CONFIG='experimental-features = nix-command flakes' nix build github:gh-xj/public-dotfiles#homeConfigurations.example.activationPackage
```

Apply the checked-in host only from a matching test account named `example`, or
after cloning and editing `hosts/example.nix` for your own macOS user:

```bash
NIX_CONFIG='experimental-features = nix-command flakes' nix run github:nix-community/home-manager/master -- switch --flake .#example
```

See [docs/bootstrap.md](docs/bootstrap.md) for the direct public bootstrap path
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
- private overlay and sensitive-state owner: `gh-xj/private-config`
  (`https://github.com/gh-xj/private-config`)

Do not rename these to `dotfiles-public` or `dotfiles-private`; those names are
only conceptual roles in older planning notes.

## Scope

This repo keeps reusable and publishable configuration that affects daily
operating comfort:

- shell and terminal config
- editor config
- CLI tool config
- public-safe package and GUI app ledgers
- window manager and desktop preferences
- public-safe Claude/Codex policy and baseline settings

Private agent runtime state, credentials, custom provider endpoints,
project-trust lists, company/private settings, marketplace state, generated
state, caches, sessions, and personal archives belong in `private-config` or
runtime-owned local state, not here.

## Install

Canonical local Home Manager entrypoint for a real macOS user:

```bash
./scripts/bootstrap-macos.sh --apply
```

This backs up pre-existing unmanaged Home Manager link targets by default. For
a strict conflict check:

```bash
./scripts/bootstrap-macos.sh --apply --no-backup
```

For the GUI app/Homebrew ledger as well:

```bash
./scripts/bootstrap-macos.sh --darwin --apply
```

`task install` remains a maintainer shortcut for the checked-in `.#example`
configuration. Use it only from a clone whose `hosts/example.nix` matches the
target macOS account. A private host may import this repo, but that private
overlay should only add sensitive, account-bound, or runtime-adjacent state.

## Nix Package Sets

The public flake exports named package sets:

- `packageSets.shell`
- `packageSets.dev`
- `packageSets.ops`

The default public Home Manager module composes all package sets for
`homeConfigurations.example`. The sets are intentionally hard-cut to tools
that are either daily reach-for commands or direct dependencies of this repo's
shell, editor, terminal, agent, and verification surfaces. A host can choose a
subset:

```nix
{
  xj.publicDotfiles = {
    enable = true;
    packageSets = [ "shell" "dev" ];
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

The public repo should be enough to restore the public-safe parts of xj's
operating environment on a clean machine.

- build the example with `NIX_CONFIG='experimental-features = nix-command flakes' nix build .#homeConfigurations.example.activationPackage`
- run `./scripts/bootstrap-macos.sh` first on a new macOS machine
- use `./scripts/bootstrap-macos.sh --apply` for a real target user
- use `./scripts/bootstrap-macos.sh --darwin --apply` when the public
  nix-darwin/Homebrew app ledger should be applied too
- edit `hosts/example.nix` only when intentionally testing the checked-in example host
- run `task install` only after the local example host matches that user
- use `private-config` only when the machine needs sensitive, account-bound,
  company/private, secret-adjacent, or runtime-adjacent overlays
- the public repo owns reusable public-safe comfort config; the private repo is
  an optional overlay for private durable state

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
