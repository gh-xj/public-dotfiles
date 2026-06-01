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

The bootstrap supports both Apple Silicon and Intel Macs. `--darwin --apply`
uses `sudo` for `darwin-rebuild switch`. If Homebrew is missing from the
platform default prefix (`/opt/homebrew/bin/brew` on Apple Silicon,
`/usr/local/bin/brew` on Intel), the script first runs Homebrew's official
installer:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

nix-darwin then manages the public Homebrew taps, formulae, fonts, and GUI
casks declared by `public-dotfiles`.

For remote runs, use an interactive SSH session or pre-authorize sudo on the
target machine before `--darwin --apply`; non-interactive SSH without cached
sudo credentials fails before the long build/apply phase.

On first nix-darwin activation, existing `/etc/bashrc` and `/etc/zshrc` often
come from stock macOS plus the Nix installer. The bootstrap backs them up to
`.before-nix-darwin` before `darwin-rebuild switch` so nix-darwin can own the
generated system shell files. Use `--no-migrate-nix-darwin-etc` when you want
to inspect and rename those files manually.

This command still proves the public Home Manager example evaluates and builds
without touching your home directory:

```bash
NIX_CONFIG='experimental-features = nix-command flakes' nix build github:gh-xj/public-dotfiles#homeConfigurations.example.activationPackage
```

## Apply With Home Manager

For a real macOS user account, prefer the generated local bootstrap host:

```bash
./scripts/bootstrap-macos.sh --apply
```

By default, `--apply` passes a timestamped backup extension to Home Manager so
unmanaged files that already exist at Home Manager-owned paths are moved aside
instead of blocking the bootstrap. Use `--backup-extension EXT` for a custom
extension, or `--no-backup` when you want a strict conflict failure.

Verify the user-level surface after Home Manager apply:

```bash
task dotfiles:verify-user
```

## Codex Runtime Config

The public repo owns `.codex/config.toml` as a template, not as a live Home
Manager link. During `--apply`, Home Manager seeds
`~/.codex/config.toml` from that template only when the live file is missing or
still points at an old read-only public Nix store generation. After seeding,
the live file remains a normal writable runtime file so Codex can persist
project trust, marketplace state, hook state, and other TUI updates.

If Codex shows `config/batchWrite failed in TUI` after a direct public apply,
rerun the public bootstrap once:

```bash
./scripts/bootstrap-macos.sh --apply
```

Then verify the boundary:

```bash
./scripts/verify-codex-runtime-boundary.sh --live
```

## Raycast Script Commands

Home Manager syncs the public Script Command files, but Raycast still needs one
interactive app-owned step before those commands are searchable and before
their aliases/hotkeys can be configured.

After `--apply`, run:

```bash
task raycast:open-script-setup
```

This copies the stable Script Directory path and opens Raycast Settings. In the
Raycast UI, add this directory under `Extensions -> Script Commands`:

```text
~/public-dotfiles/.config/raycast/scripts
```

Use the repo path above, not `~/.config/raycast/scripts`, because the Home
Manager live path points through a generated Nix store path. After adding the
directory, configure per-command aliases and hotkeys from Raycast search with
`Configure Command`.

`task raycast:runtime-check` verifies the repo-owned files and reports this
runtime boundary. It may still warn that Script Directory registration,
aliases, and hotkeys are not visible in plaintext defaults. That warning is
expected after manual setup; Raycast keeps that state in app-managed data or
encrypted `.rayconfig` exports. Treat user confirmation that the commands
appear in Raycast search as the acceptance signal.

For the public app ledger as well:

```bash
./scripts/bootstrap-macos.sh --darwin --apply
```

Verify the full public surface after the Darwin/Homebrew phase:

```bash
task dotfiles:verify
```

If verification reports a live `AppleMultitouchDevice` mismatch while the
persisted trackpad defaults are correct, run this from the target Mac or an
interactive SSH session:

```bash
task input:reload-live
task input:verify
```

If the live state still does not change, log out and back in before rerunning
`task input:verify`.

Pass other Home Manager flags after `--`:

```bash
./scripts/bootstrap-macos.sh --apply -- --show-trace
```

The public flake also exports `homeConfigurations.example`. The checked-in host
uses `home.username = "example"` and `home.homeDirectory = "/Users/example"` so
it is safe to build without assuming xj's local account. Apply it directly only
in a matching throwaway test account:

```bash
NIX_CONFIG='experimental-features = nix-command flakes' nix run github:nix-community/home-manager/master -- switch --flake github:gh-xj/public-dotfiles#example
```

For local maintainer testing of the checked-in example host:

```bash
NIX_CONFIG='experimental-features = nix-command flakes' nix run github:nix-community/home-manager/master -- switch --flake .#example
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
