# Public Bootstrap

`public-dotfiles` is the public-safe split of xj's macOS configuration. It owns
the non-sensitive shell, editor, terminal, CLI, GUI app, package, and agent
defaults needed to restore a comfortable operating environment. It can be
applied directly with Home Manager or imported by a private flake. It
deliberately excludes credentials, app sessions, private provider endpoints,
company/private settings, project trust lists, and machine-local runtime state.

## Fastest Read-Only Check

From a fresh macOS clone, the first command should be:

```bash
./scripts/bootstrap-macos.sh
```

The default mode is a non-mutating preflight. It checks the machine, generates a
local Home Manager host under `~/.local/state/public-dotfiles/bootstrap/`, and
builds the activation package when Nix is already available.

On a stock Mac without Nix, the script reports the missing dependency and prints
both upstream install commands. To let it install Nix and then apply Home
Manager, run:

```bash
./scripts/bootstrap-macos.sh --install-nix --apply
```

The default `--install-nix` mode uses the official macOS daemon installer. Use
`--install-nix=determinate` when you explicitly want the Determinate CLI
installer instead.

## macOS System Phase

The default bootstrap path is user-level Home Manager. To also build the public
nix-darwin host and apply the Homebrew GUI/app ledger, opt in explicitly:

```bash
./scripts/bootstrap-macos.sh --darwin --apply
```

`--darwin` is safe in dry-run mode:

```bash
./scripts/bootstrap-macos.sh --darwin
```

It builds the generated Home Manager activation package and generated
nix-darwin system when Nix is available, but does not run `home-manager switch`,
install Homebrew, or call `darwin-rebuild switch`.

`--darwin --apply` uses `sudo` for `darwin-rebuild switch`. If Homebrew is
missing from `/opt/homebrew/bin/brew`, the script first runs Homebrew's official
installer:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

nix-darwin then manages the public Homebrew taps, formulae, fonts, and GUI
casks declared by `public-dotfiles`.

This command still proves the public Home Manager example evaluates and builds
without touching your home directory:

```bash
nix build github:gh-xj/public-dotfiles#homeConfigurations.example.activationPackage
```

## Apply With Home Manager

For a real macOS user account, prefer the generated local bootstrap host:

```bash
./scripts/bootstrap-macos.sh --apply
```

For the public app ledger as well:

```bash
./scripts/bootstrap-macos.sh --darwin --apply
```

Pass Home Manager flags after `--`:

```bash
./scripts/bootstrap-macos.sh --apply -- --backup-extension hm-backup
```

The public flake also exports `homeConfigurations.example`. The checked-in host
uses `home.username = "example"` and `home.homeDirectory = "/Users/example"` so
it is safe to build without assuming xj's local account. Apply it directly only
in a matching throwaway test account:

```bash
nix run github:nix-community/home-manager/master -- switch --flake github:gh-xj/public-dotfiles#example
```

For local maintainer testing of the checked-in example host:

```bash
nix run github:nix-community/home-manager/master -- switch --flake .#example
```

## Package Set Selection

The public flake exports named package sets:

- `packageSets.shell`
- `packageSets.dev`
- `packageSets.ops`

The default Home Manager module installs all three. The default package lists
are deliberately small: shell/editor/git/tmux/yazi, current dev workflow, and
repo verification helpers. A host can select a subset:

```nix
{
  xj.publicDotfiles = {
    enable = true;
    packageSets = [ "shell" "dev" ];
  };
}
```

Downstream flakes can also import package sets directly:

```nix
{ inputs, pkgs, ... }:

{
  home.packages =
    inputs.public.packageSets.shell pkgs
    ++ inputs.public.packageSets.dev pkgs
    ++ inputs.public.packageSets.ops pkgs;
}
```

## What This Does Not Restore

Nix does not restore macOS TCC grants, GUI app sessions, browser profiles, App
Store purchases, login items, privileged helpers, runtime auth tokens, or
private project trust lists. Keep those in a private overlay or set them up
manually on each machine.
