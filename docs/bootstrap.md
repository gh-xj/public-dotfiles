# Public Bootstrap

This repo can restore the public-safe macOS baseline by itself. A private flake
may import it, but is not required.

## Supported Entry Point

Start with the non-mutating preflight:

```bash
./scripts/bootstrap-macos.sh
```

It detects the Darwin platform, generates a machine-local host under
`~/.local/state/public-dotfiles/bootstrap/`, and builds the Home Manager
activation package when Nix is available.

Apply the user-level baseline only when requested:

```bash
./scripts/bootstrap-macos.sh --apply
```

Opt into the nix-darwin and Homebrew system phase explicitly:

```bash
./scripts/bootstrap-macos.sh --darwin --apply
```

`--darwin` without `--apply` builds the generated Home Manager and nix-darwin
outputs without switching them. Run `./scripts/bootstrap-macos.sh --help` for
the current option list; the script is the option source of truth.

## First-Run Safety

- `--apply` backs up unmanaged Home Manager targets with a timestamped
  extension. Use `--no-backup` to fail on conflicts instead.
- `--darwin --apply` may use `sudo`. Over SSH, use an interactive session or
  pre-authorize sudo before the long build.
- On first nix-darwin activation, the script backs up existing `/etc/bashrc`
  and `/etc/zshrc` to `.before-nix-darwin`. Use
  `--no-migrate-nix-darwin-etc` for a strict failure.
- Homebrew installation is opt-in through the Darwin apply path when Homebrew
  is absent. Use `--no-install-homebrew` to require a pre-existing install.
- Pass Home Manager arguments after `--`, for example
  `./scripts/bootstrap-macos.sh --apply -- --show-trace`.

On a stock Mac without Nix, use `--install-nix --apply`. The default is the
official daemon installer; `--install-nix=determinate` selects the Determinate
installer. Intel Macs older than macOS 14 default to Nix `2.29.4` because newer
x86_64-darwin binaries can require macOS 14 symbols.

If an installer left `/nix/store` without a usable Nix profile, the bootstrap
stops. Follow the installer's official macOS uninstall procedure before retrying
instead of layering another install over partial APFS state.

## Read-Only Builds And Verification

Build the host-native checked-in example without activating it:

```bash
NIX_CONFIG='experimental-features = nix-command flakes' nix build "$(./scripts/home-config-attr.sh activation-package)"
```

The checked-in examples target the user `example`; `task apply` refuses to run
for a different current user. Real users should use the generated bootstrap
host above or intentionally adapt `hosts/example.nix` in their own clone.

After a user or Darwin apply, run:

```bash
task check
```

For changes to bootstrap generation, also use the focused read-only gate:

```bash
task verify:bootstrap-darwin
```

## Package Sets

The Home Manager module enables `shell`, `dev`, and `ops` by default. A
downstream host can choose a subset:

```nix
{
  xj.publicDotfiles = {
    enable = true;
    packageSets = [ "shell" "dev" ];
  };
}
```

The package lists live under `packages/`; do not duplicate them in docs.

## Interactive Boundaries

The repo cannot silently restore TCC grants, GUI sessions, browser profiles,
App Store purchases, login-item consent, auth tokens, or project trust lists.

Raycast also owns Script Command directory registration, aliases, hotkeys, and
Store install confirmation. After apply, register the clone's
`.config/raycast/scripts` directory in Raycast Settings under
`Extensions -> Script Commands`. Check Store extensions with
`task verify:raycast-extensions`; open missing install intents with
`task raycast:open-extension-installs` and approve them in Raycast.

Persisted macOS defaults can match while the GUI session or hardware state is
stale. For display and input discrepancies, follow
`docs/macos-convergence-model.md` before adding another declaration or verifier.
