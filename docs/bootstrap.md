# Bootstrap a fresh Mac with the public baseline

This is the canonical public-only sequence. For an existing nix-darwin work
Mac, use [the migration runbook](migrate-work-mac.md) instead. Run all commands
as the logged-in user unless a step says **human only**; this public flow has no
sudo step.

## Migration checklist

- [ ] Install Command Line Tools, Determinate Nix, and Homebrew
- [ ] Clone `public-dotfiles`
- [ ] Build and check before activation
- [ ] Apply Home Manager and start a clean shell
- [ ] Install Brewfile apps and locked mise tools
- [ ] Run final checks and complete interactive setup
- [ ] Record the rollback boundary

## 1. Install prerequisites — human only

Install Apple's Command Line Tools from the prompt, then install Determinate
Nix and Homebrew from their official installers:

```bash
xcode-select --install
curl --proto '=https' --tlsv1.2 -sSf -L \
  https://install.determinate.systems/nix | sh -s -- install
/bin/bash -c "$(curl -fsSL \
  https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  eval "$(/usr/local/bin/brew shellenv)"
fi
```

Open a new Terminal after the Nix installer finishes. Verify:

```bash
xcode-select -p
/nix/var/nix/profiles/default/bin/nix --version
brew --version
```

Expected: a Developer directory, `nix (Nix) ...`, and `Homebrew ...`. Stop if
any prerequisite is missing.

## 2. Clone the public repository — human or agent

```bash
git clone https://github.com/gh-xj/public-dotfiles.git ~/public-dotfiles
cd ~/public-dotfiles
git status --short --branch
```

Expected: `## main...origin/main` with no changed paths.

## 3. Build and check before activation — human or agent

`task` and `gitleaks` are not installed yet, so use a temporary Nix shell:

```bash
cd ~/public-dotfiles
nix shell nixpkgs#go-task nixpkgs#gitleaks -c task check
nix shell nixpkgs#go-task nixpkgs#gitleaks -c task plan
```

Expected: `public dotfiles check passed`; the plan prints a `/nix/store/...`
generation and a home change report. Neither command activates it.

## 4. Apply Home Manager — human only

```bash
cd ~/public-dotfiles
nix shell nixpkgs#go-task -c task apply
```

Expected: `Home Manager and macOS settings apply complete`. The script creates
the machine-local flake below `~/.local/state/public-dotfiles/bootstrap/` and
switches only the user profile.

Already-open shells and agents still carry the old `PATH` and possibly the old
nix-darwin `NIX_SSL_CERT_FILE`. Open a new shell. For an agent, use an empty
environment:

```bash
env -i HOME="$HOME" USER="$USER" /bin/zsh -lc \
  'command -v task; print -r -- ${NIX_SSL_CERT_FILE-unset}'
```

Expected: `~/.local/state/nix/profiles/home-manager/home-path/bin/task` followed
by `unset`.

## 5. Install apps and runtimes — human only

```bash
cd ~/public-dotfiles
task apps
brew bundle check --file Brewfile --no-upgrade
mise ls --current
```

Expected: Brew reports dependencies satisfied, and mise lists the versions locked in
`config/mise/mise.lock`. `task apps` runs `brew bundle --no-upgrade` and `mise
install --locked`; it never runs cleanup.

The public `Brewfile` declares no third-party taps; review any tap prompt
instead of blindly accepting it. The repo config and `.zshenv` trust
`~/.config/mise/config.toml`; if mise still prompts after checking that exact
path, run:

```bash
mise trust ~/.config/mise/config.toml
mise trust --show ~/.config/mise/config.toml
```

Expected: mise reports the file as trusted.

## 6. Verify and finish first-run setup — human or agent

Use a clean shell so provenance is not measured against stale environment:

```bash
env -i HOME="$HOME" USER="$USER" /bin/zsh -lc '
  cd "$HOME/public-dotfiles" && task check && task doctor
'
```

Expected: `public dotfiles check passed`, `command provenance: ... 0 issue(s)`,
and no drift failures. Also verify the intentional providers:

```bash
env -i HOME="$HOME" USER="$USER" /bin/zsh -lc '
  command -v docker
'
```

Expected: Docker resolves below `~/.orbstack/bin`.

Complete these interactive items manually: app sign-ins, macOS TCC grants,
Raycast Cloud Sync (hotkeys and extensions), and any application first-run
dialogs. Home Manager cannot reproduce those permissions or sessions.

## Rollback boundary

Before the first successful activation, the rollback boundary is the clean Git
checkout; no Home Manager generation exists yet. After two or more successful
generations, roll the user profile back with:

```bash
cd ~/public-dotfiles
task rollback
readlink ~/.local/state/nix/profiles/home-manager
```

Expected: the profile link moves to the previous `home-manager-*-link` and its
activation completes. This does not uninstall apps. Remove extras individually;
never use `brew bundle cleanup`.

## Package and config ownership after bootstrap

Run `task doctor` whenever a command resolves from more than one provider.
Common legacy locations are Homebrew formulae, `npm -g`, `~/go/bin`,
`~/.cargo/bin`, `~/.bun/bin`, and an old npm-global prefix. Before removing one,
search tracked config for hard-coded executable paths:

```bash
git -C ~/public-dotfiles grep -n '/opt/homebrew/bin/' -- . || true
type -a gh node go cargo bun
```

Uninstall the extra owner, or use `brew unlink <formula>` when the formula is
only a dependency. If shell startup mentions a binary that was removed, clear
the path-keyed generated init files with `rm -f ~/.cache/*-init.zsh(N)`, then
open a new shell.

Hand-edited config is delivered as a live repo link; agent settings stay writable and
re-merge declared keys on each apply. Config-only edits therefore do not need
`task apply`. Reload existing tmux with `tmux source-file ~/.tmux.conf`; use
Ghostty's Reload Configuration action. Package or Nix module changes still need
`task apply`.

An improvement found on this Mac that every Mac would want goes to
`~/public-dotfiles/.upstream/` as a proposal for the lead session, not as a
local commit: see [upstream proposals](downstream-composition.md#upstream-proposals).
