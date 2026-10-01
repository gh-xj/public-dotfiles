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

### Upgrade from the old Ghostty parent symlink

Before switching, bootstrap checks `~/.config/ghostty`. If it is the known link
to this checkout's `.config/ghostty`, apply removes only that link and creates a
real directory for the generated leaf. The linked target and its contents are
preserved. This also handles a dangling link after the old repo config was
removed. The migration is idempotent and included before Home Manager's link
checks so downstream overlays receive it too.

An unrelated parent symlink is an actionable error, including in dry-run. It is
not covered by the automatic leaf-backup option: inspect and move it aside
explicitly, then retry. A `.config` ancestor pointing into the checkout is also
rejected. Bootstrap dry-run only reports planned migration; apply performs it
before Home Manager switch. The generated Ghostty config must never be written
back into the checkout.

After an upgrade, run `python3 scripts/verify-ghostty.py --live` from this repo.
For a private overlay, run that overlay's apply first. See
[Ghostty upgrade details](ghostty-tmux.md#upgrading-the-legacy-ghostty-directory-link)
for effective-settings checks and existing-surface reload limitations.

### Other first-run behavior

- `--apply` backs up unmanaged Home Manager targets with a timestamped
  extension.
- `--darwin --apply` may use `sudo`. Over SSH, use an interactive session or
  pre-authorize sudo before the long build.
- On first nix-darwin activation, the script backs up existing `/etc/bashrc`
  and `/etc/zshrc` to `.before-nix-darwin`.
- Homebrew installation is opt-in through the Darwin apply path when Homebrew
  is absent.

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
NIX_CONFIG='experimental-features = nix-command flakes' nix build .#
```

`task apply` generates a host for the current user and runs the Home Manager
and nix-darwin phases. The checked-in `example` hosts remain build fixtures.

After a user or Darwin apply, run:

```bash
task check
```

For read-only source/generation/runtime diagnosis, run `task doctor`; add
`-- --flake PATH#PROFILE` to compare generated output and `-- --live` for
runtime checks. Apply changes only through `task apply`.

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
`Extensions -> Script Commands`. Run `task raycast:install` to verify the
ledger, open missing install intents, and approve them in Raycast.

Persisted macOS defaults can match while the GUI session or hardware state is
stale. For display and input discrepancies, follow
`docs/macos-convergence-model.md` before adding another declaration or verifier.
