# Student Bootstrap

`public-dotfiles` is a public-safe macOS baseline for shell, editor, terminal,
CLI, and agent policy. It can be built directly as a Home Manager example,
imported by a private flake, or installed as direct `$HOME` symlinks through
`configctl`. It deliberately excludes credentials, app sessions, private
provider endpoints, project trust lists, and machine-local runtime state.

## Fastest Read-Only Check

This command proves the public Home Manager example evaluates and builds
without touching your home directory:

```bash
nix build github:gh-xj/public-dotfiles#homeConfigurations.example.activationPackage
```

## Apply With Home Manager

The public flake exports `homeConfigurations.example`. It is intentionally a
teaching fixture, with `home.username = "example"` and
`home.homeDirectory = "/Users/example"`. Apply it directly only in a matching
throwaway test account:

```bash
nix run github:nix-community/home-manager/master -- switch --flake github:gh-xj/public-dotfiles#example
```

For a real user account, fork or clone the repo, edit `hosts/example.nix` to
match your macOS username and home directory, then switch from the local clone:

```bash
nix run github:nix-community/home-manager/master -- switch --flake .#example
```

## Apply With configctl

If you want the same public files linked into your current `$HOME` without
adopting Home Manager first, clone the repo and run:

```bash
task install
```

Use a dry run before applying on an existing machine:

```bash
task install -- --dry-run
```

If you need private or machine-local files but do not have access to xj's real
private repo, scaffold a local-only private overlay:

```bash
task private:init
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

Nix and `configctl` do not restore macOS TCC grants, GUI app sessions, browser
profiles, App Store purchases, login items, privileged helpers, runtime auth
tokens, or private project trust lists. Keep those in a private overlay or set
them up manually on each machine.
