# Current Machine Baseline

Date: 2026-06-01

This document captures the public-safe setup observed on xj's current Mac and
the restore surface that `public-dotfiles` should own for a new Mac. Sensitive
or account-bound state stays in `private-config`.

For the layer model used when source and target Macs disagree, see
`docs/macos-convergence-model.md`.

## Ownership Boundary

| Surface | Public baseline | Private / manual boundary |
| --- | --- | --- |
| Shell, terminal, editor, window manager, keyboard config | Home Manager links repo-backed files | Shell secrets, SSH, npm auth, account tokens |
| macOS Dock/Finder/keyboard/mouse/trackpad defaults | nix-darwin `system.defaults` | TCC grants and login-item consent |
| Display layout / resolution | `displayplacer` is installed, known display serials are applied and verified | Unknown display hardware is inspected but not changed |
| GUI app install ledger | nix-darwin Homebrew module | App sessions, sync accounts, caches |
| Raycast | App install, public-safe preferences, repo-owned script commands, and a desired Store extension ledger | Raycast account DB, extension cache, extension credentials, `raycast_env` |
| CLI packages | Nix package sets first | Per-account credentials and generated caches |

## macOS Defaults

These values were read from `/Users/xj` and encoded in
`modules/darwin/defaults.nix`.

| Area | Baseline |
| --- | --- |
| Dock | autohide on, delay `0`, animation `0.5`, recents off, tile size `71`, group windows by app, keep MRU Spaces behavior |
| Dock persistent items | public minimal Dock: Chrome, Ghostty, and Downloads. Local-only apps such as Feishu, WeChat, and Timing are observed but not forced unless they join the public app ledger |
| Finder | show file extensions, column view, path bar enabled |
| Keyboard | press-and-hold disabled, `KeyRepeat=1`, `InitialKeyRepeat=10`, function keys as standard keys |
| Language/input | English plus Simplified Chinese language list; U.S. keyboard plus Simplified Chinese Shuangpin input source |
| Mouse / trackpad speed | mouse scaling `3`, trackpad scaling `3` |
| Trackpad | tap to click, right click, three-finger drag, light click thresholds, four-finger gestures, three-finger horizontal/vertical gestures disabled |
| Input defaults | ByHost keys in `config/macos/current-host-defaults.tsv`, user input keys in `config/macos/input-user-defaults.tsv`, and live trackpad expectations in `config/macos/live-trackpad-defaults.tsv` |
| Magic Mouse | two-button mode |
| Symbolic hotkeys | local Apple symbolic hotkey enablement and parameters copied for ids `15-31`, `52`, `60-65`, `79-82`, `118-122`, `164`, `184` |
| Appearance | automatic light/dark switching enabled |
| Spaces | desired count is `4`; verification is available but not blocking because creation requires Mission Control UI automation and Accessibility consent |
| Display layout | known serials: Studio Display XDR `2880x1620@120Hz`, M1 MacBook built-in `1680x1050@60Hz` |

## Repo-Backed User Config

Home Manager now owns these public config files on a new machine:

| Path | Source |
| --- | --- |
| `~/.zprofile`, `~/.zshrc` | repo shell entrypoints |
| `~/.tmux.conf`, `~/.config/tmux/tmux.conf` | Home Manager tmux config |
| `~/.config/ghostty/config` | Home Manager Ghostty config |
| `~/.config/nvim` | repo Neovim config |
| `~/.config/karabiner` | repo Karabiner config |
| `~/.amethyst.yml`, `~/.config/amethyst` | repo Amethyst config |
| `~/.config/bat`, `~/.config/lazygit`, `~/.config/yazi`, `~/.config/starship.toml` | repo CLI config |
| `~/.config/opencode` | repo opencode config |

## App And Tool Baseline

| Source | Baseline |
| --- | --- |
| Nix shell set | `atuin`, `bat`, `btop`, `eza`, `fd`, `fzf`, `git`, `glow`, `hyperfine`, `jq`, `ripgrep`, `starship`, `tealdeer`, `trash`, `yazi`, `zoxide`, zsh plugins |
| Nix dev set | `go`, `go-task`, `lazygit`, `neovim`, `nodejs`, `prettier`, `rust`, `shfmt`, `tmux`, `uv`, `delta`, `difftastic` |
| Nix ops set | `claude-code`, `codex`, `gh`, `gitleaks` |
| npm globals | narrow public ledger in `npm-globals.txt`; currently `ccusage@20.0.6` |
| Homebrew brews | `displayplacer`, `gemini-cli`, `googleworkspace-cli`, `markdownlint-cli2`, `marksman`, `mole`, `pngpaste` |
| Homebrew casks | Ghostty, Chrome, Karabiner, Amethyst, Raycast, OrbStack, ChatGPT, Codex app, Setapp, TypeWhisper, Mimestream, 1Password, CleanShot, Tailscale, public font set |

## Raycast Current State

The local Raycast cache contains many Store extensions, including Chrome,
Ghostty, GitHub, Brew, Docker, Lark, Mole, TypeWhisper, CleanShot, Raycast
system monitor, port/process tools, emoji/date/color utilities, and several
AI/social/search helpers. That extension cache is app-local runtime state, not
a good public source of truth.

The durable public baseline is:

1. Install Raycast.
2. Apply public-safe Raycast preferences: compact mode, Vim navigation,
   dark/light bundled themes, `Command-Space` hotkey, favorite visibility,
   root search sensitivity, quicklink behavior, and onboarding state.
3. Link public script commands at `~/.config/raycast/scripts`.
4. Track desired public Store extensions in `config/raycast/extensions.tsv`.
5. Keep `raycast_env`, extension credentials, account sync, and private
   workflow scripts in `private-config`.

The public script-command set currently covers opening Chrome, ChatGPT, and
Ghostty; inserting date/datetime strings; and switching to the Shuangpin input
source. Scripts that reveal private paths, employer context, Bluetooth device
IDs, or personal workflow repos stay private.

Raycast Store extensions are not copied from caches. Run
`task verify:raycast-extensions` to list missing desired extensions, or
`task raycast:open-extension-installs` to open Raycast install intents for
missing extensions. Raycast's documented install path is still the in-app or web
Store, so this check is intentionally outside the blocking `dotfiles:verify`
gate.

Spaces creation is also outside the blocking gate. Run
`task spaces:request-permission` to open macOS Accessibility settings for the
current automation context, then `task spaces:apply` once consent is granted.

## Baseline Inspection

Run `task inspect:macos-baseline` on any Mac to print the public-safe inventory
used for discrepancy triage. It reports display hardware and displayplacer
state, global keyboard/mouse defaults, persisted input defaults, live trackpad
state, input sources, Dock items, Spaces count, Raycast preferences, Raycast
extensions, and Raycast script-command directories.

## Verification

| Gate | What it protects |
| --- | --- |
| `task verify:home-files` | Home Manager generation contains the public config files above |
| `task verify:bootstrap-darwin` | The generated nix-darwin bootstrap host still builds |
| `task verify:display-layout` | Known display serials match the displayplacer layout policy |
| `task verify:macos-defaults` | The current host matches the public macOS defaults baseline |
| `task input:apply` | Apply persisted input defaults and reload live trackpad state |
| `task input:verify` | Verify persisted input defaults plus live `AppleMultitouchDevice` state |
| `task verify:raycast` | The current host matches public-safe Raycast preferences |
| `task verify:raycast-extensions` | Desired public Raycast Store extensions are installed |
| `task verify:spaces` | Mission Control Spaces count matches the desired count |
| `task spaces:request-permission` | Opens Accessibility settings for Spaces automation |
| `task spaces:apply` | Attempts to create missing Mission Control Spaces |
| `task inspect:macos-baseline` | Prints local setup state for source/target comparison |
| `task verify:terminal` | Ghostty, Karabiner, and tmux terminal workflow invariants |
