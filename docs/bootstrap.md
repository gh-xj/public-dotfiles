# Public Bootstrap

`public-dotfiles` is the public-safe split of xj's macOS configuration. It owns
the non-sensitive shell, editor, terminal, CLI, GUI app, package, and agent
defaults needed to restore a comfortable operating environment. It can be
applied directly with Home Manager or imported by a private flake. It
deliberately excludes credentials, app sessions, private provider endpoints,
company/private settings, project trust lists, and machine-local runtime state.

## Fastest Read-Only Check

This command proves the public Home Manager example evaluates and builds
without touching your home directory:

```bash
nix build github:gh-xj/public-dotfiles#homeConfigurations.example.activationPackage
```

## Apply With Home Manager

The public flake exports `homeConfigurations.example`. The checked-in host uses
`home.username = "example"` and `home.homeDirectory = "/Users/example"` so it
is safe to build without assuming xj's local account. Apply it directly only in
a matching throwaway test account:

```bash
nix run github:nix-community/home-manager/master -- switch --flake github:gh-xj/public-dotfiles#example
```

For a real user account, fork or clone the repo, edit `hosts/example.nix` to
match your macOS username and home directory, then switch from the local clone:

```bash
nix run github:nix-community/home-manager/master -- switch --flake .#example
```

## Package Set Selection

The public flake exports named package sets:

- `packageSets.shell`
- `packageSets.dev`
- `packageSets.ops`
- `packageSets.teaching`

The default Home Manager module installs all four. A host can select a subset:

```nix
{
  xj.publicDotfiles = {
    enable = true;
    packageSets = [ "shell" "dev" "teaching" ];
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
