# public-dotfiles

`public-dotfiles` is the public-safe split of xj's macOS configuration. It owns
the non-sensitive shell, editor, terminal, CLI, GUI app, package, and agent
defaults needed to restore a comfortable operating environment. It can be
applied directly with Home Manager or imported by a private flake. Credentials,
app sessions, provider endpoints, project trust lists, company/private settings,
and machine-local runtime state stay out of this repo.

## Quick Start

Install Determinate Nix and Homebrew, then clone this repo. From the clone:

```bash
task apply
task apps
```

`task apply` creates a machine-local standalone Home Manager host under
`~/.local/state/public-dotfiles/bootstrap/`, switches only the user profile,
and applies declared user-level macOS settings. `task apps` applies the Brewfile
without cleanup and installs the locked mise toolset.

Preview the Home Manager generation without activating it:

```bash
task plan
```

After apply, run `task check`. The bootstrap supports Apple Silicon and Intel;
the Brewfile retains its macOS-version gates for newer casks. Existing unmanaged
Home Manager targets receive a timestamped backup extension.

For daily plan, diagnosis, and scoped apply commands from any directory, see
[Daily dotfiles operations](docs/dotfiles-operations.md).

You can still build the host-native public Home Manager example without
touching your home directory:

```bash
NIX_CONFIG='experimental-features = nix-command flakes' nix build .#
```

Apply the checked-in host only from a matching test account named `example`, or
after cloning and editing `hosts/example.nix` for your own macOS user:

```bash
NIX_CONFIG='experimental-features = nix-command flakes' nix run github:nix-community/home-manager/master -- switch --flake .#example
```

See [docs/bootstrap.md](docs/bootstrap.md) for the direct public bootstrap path
and package set selection.
See [docs/default-openers.md](docs/default-openers.md) for durable Markdown/PDF
opening preferences.
See [docs/zed.md](docs/zed.md) for the graphical review workflow and Neovim-aligned keys.

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
- public global go-task Taskfile
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
task apply
```

This backs up pre-existing unmanaged Home Manager link targets by default.

Apply the GUI app/Homebrew ledger separately with `task apps`. `task apply`
refuses
to apply over the current user when an adjacent `private-config` composes that
profile. A private host may import this repo, but that private overlay should
only add sensitive, account-bound, or runtime-adjacent state.

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

Home Manager also installs mise and delivers the locked public runtime and npm
CLI declarations at `~/.config/mise/`. `task apps` installs them after applying;
language runtimes and ecosystem CLIs do not belong in the Nix package sets.

## Agent Baseline

This repo now publishes the reusable Claude/Codex baseline:

- `~/.claude/CLAUDE.md`
- `config/claude/settings.json` as merged writable settings
- `~/.claude/statusline-command.sh`
- `~/.codex/AGENTS.md`
- `~/.codex/rules/default.rules`
- `config/codex/config.toml` as the public Codex seed template

Claude settings and Codex hooks stay writable live files: each `task apply`
three-way merges the declared keys into them and keeps runtime-only edits.
Agent helpers are installed through Home Manager; global guard/formatter hooks
are retired in favor of native permissions and repo-local formatting.

The private repo continues to own agent runtime and account-local material such
as `settings.local.json`, plugin registry state, skills trees, sessions, auth,
and per-project trust or provider overrides. The public bootstrap seeds
`~/.codex/config.toml` only when it is missing or still an old read-only public
Home Manager symlink; after that, the live file stays writable for Codex TUI
trust, marketplace, hook, and runtime updates. A short reference lives in
`docs/agent-config.md`. The broader Home Manager delivery model is documented in
`docs/config-delivery-model.md`.

Project-local public skills that operate this repo may live under
`.claude/skills/`, with `.agents/skills/` used only as a Codex discovery
adapter. Those are not global home skill trees.

## Onboarding notes

The public repo should be enough to restore the public-safe parts of xj's
operating environment on a clean machine.

- build the host-native example with `NIX_CONFIG='experimental-features = nix-command flakes' nix build .#`
- install Determinate Nix and Homebrew, clone the repo, then run `task apply`
- run `task apps` for the Brewfile and locked mise runtimes
- edit `hosts/example.nix` only when intentionally testing the checked-in example host
- use `task apply` as the standalone Home Manager path
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
