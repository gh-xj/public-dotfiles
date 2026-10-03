# Public Bootstrap

This repo restores the public-safe baseline with standalone Home Manager. A
private flake may import `homeModules.default`, but is not required.

## Fresh Mac

Install Determinate Nix and Homebrew, then clone the repo:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L \
  https://install.determinate.systems/nix | sh -s -- install
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
git clone https://github.com/gh-xj/public-dotfiles.git ~/public-dotfiles
cd ~/public-dotfiles
task apply
task apps
task check
```

`task apply` requires the two prerequisites. It generates a machine-local Home
Manager flake under
`~/.local/state/public-dotfiles/bootstrap/`, backs up unmanaged link targets,
switches only the user profile, and applies declared user-level macOS settings
without sudo.

`task apps` runs `brew bundle --no-upgrade` and `mise install --locked`; it never
runs cleanup. The Brewfile gates casks that require newer macOS releases.

## Read-Only Verification

```bash
task plan
task check
nix build --no-link .#homeConfigurations.example.activationPackage
nix build --no-link .#homeConfigurations.example-x86_64.activationPackage
brew bundle check --file Brewfile --no-upgrade
```

The checked-in hosts are build fixtures. `task apply` generates the real user
profile; do not edit `hosts/example.nix` with private identities. If an adjacent
`private-config` exists, apply from that owner instead.

## First-Run Boundaries

TCC grants, browser/app accounts, encrypted runtime state, Raycast registration
and system-level macOS settings remain interactive or separately owned.

The Home Manager module enables `shell`, `dev` and `ops` package sets by
default. A downstream profile may set `xj.publicDotfiles.packageSets` to a
subset; package lists remain single-sourced under `packages/`.
