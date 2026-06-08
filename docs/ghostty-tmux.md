# Ghostty and tmux

This setup treats tmux as the primary terminal workspace layer and Ghostty as a keybinding bridge on macOS.

## Source of truth

- tmux custom config source: `~/public-dotfiles/.tmux.conf`
- tmux Home Manager module and plugin declarations: `~/public-dotfiles/modules/home/terminal.nix`
- legacy selector contract: `~/public-dotfiles/config/terminal/legacy-selectors.json`
- live tmux config: Home Manager renders `~/.config/tmux/tmux.conf`
- compatibility bridge: Home Manager renders `~/.tmux.conf` to source the live tmux config
- Ghostty config source: `~/public-dotfiles/modules/home/terminal.nix`
- Live Ghostty config: Home Manager renders `~/.config/ghostty/config`

Do not create a second standalone Ghostty config file outside Home Manager.
Do not install TPM-managed tmux plugins by hand; public tmux plugins are
declared in Nix.

## Coupling rules

Ghostty sends raw bytes into tmux for a subset of shortcuts.

- Prefix-backed tmux shortcuts must use the current tmux prefix byte in Ghostty `text:\x..` mappings.
- Option/Alt is reserved for shells and terminal applications. Do not add new tmux bridges on `\x1b...` unless the physical Alt behavior is intentionally being claimed.
- Prefer Cmd/Super in Ghostty for tmux commands, and have those mappings send prefix-backed tmux commands.
- Do not install `vim-tmux-navigator` or a local Neovim/tmux navigation bridge. Tmux owns `Ctrl-h/j/k/l`; Neovim splits use native `Ctrl-w h/j/k/l`.
- Do not rewrite physical `Ctrl-h` / `Ctrl-l` in Karabiner. They must reach tmux as real control keys.
- EasyJump is allowed only on `prefix + J`; its copy-mode `Ctrl-J` binding is unbound so it cannot compete with pane navigation.

Legacy exception:

- Some pane/window selectors still use tmux root `M-*` bindings and Ghostty `\x1b...` mappings. Treat those as migration debt, not as the preferred pattern for new shortcuts.
- Current pane selectors are `Ctrl+1..9 -> M-a/M-s/M-c/M-e/M-g/M-i/M-o/M-p/M-u`.
- Current window selectors are `Cmd+1..9 -> M-1..M-9`, and `Cmd+0 -> M-0` for the last tmux window.

Current tmux prefix:

- `Ctrl-s`
- Prefix byte: `\x13`

Native Claude Code passthrough:

- Shared tmux config enables `allow-passthrough all` so Claude Code desktop notifications and progress updates can reach Ghostty even when the agent pane/window is not currently visible.
- Shared tmux config enables `extended-keys` plus `xterm*:extkeys` so Shift+Enter remains distinguishable from Enter inside tmux.

Current pane shortcuts:

- `super+d` sends `prefix + |`: split active pane to the right and equalize pane sizes.
- `super+shift+d` sends `prefix + _`: split active pane downward and equalize pane sizes.
- `super+w` sends `prefix + X`: close the active pane immediately and equalize remaining pane sizes.
- `super+shift+enter` sends `prefix + z`: zoom or unzoom the active tmux pane.
- `super+ctrl+=` sends `prefix + E`: equalize the current tmux layout.
- `prefix + J` invokes EasyJump.
- `Ctrl-h/j/k/l` select tmux panes directly in root and copy-mode tables, even when the active pane is running nvim.
- `Ctrl-Left` / `Ctrl-Right` select tmux panes directly; `prefix + Ctrl-Left/Right` is intentionally unbound to avoid the default one-cell resize flicker.

Current pane swap behavior:

- `prefix + {` swaps the active pane with the previous pane in the current window
- `prefix + }` swaps the active pane with the next pane in the current window
- Shared config binds these explicitly with `-s .` so a marked pane in another window/session is not used as the swap source

Examples:

- `super+t=text:\x13c` means Ghostty sends `prefix c` to tmux.
- `super+d=text:\x13|` means Ghostty sends `prefix |` to tmux.

## When changing tmux prefix

If tmux prefix changes, update both:

1. `set -g prefix ...` and `bind ... send-prefix` in `~/public-dotfiles/.tmux.conf`
2. Every Ghostty prefix-backed `text:\x..` mapping in `~/public-dotfiles/modules/home/terminal.nix`

After changing tmux prefix:

1. Reload tmux config
2. Reload or restart Ghostty

## Validation

Run this after changing Ghostty, tmux, or Karabiner terminal key rules:

```bash
task verify:terminal
```

This validates Ghostty config, Karabiner complex-modification assets, tmux config parsing, the Karabiner `Ctrl-h/l` no-rewrite policy, legacy selector mappings, root `M-*` migration guards, and the EasyJump `prefix + J` only policy.

## Theme policy

The shared tmux config uses an inline theme selector.

- Shared config sets `@theme` to `dark` by default.
- Optional host-local overrides belong in `~/.tmux.local.conf`, usually `set -g @theme light` or `set -g @theme dark`.
- The shared config applies the matching light or dark inline palette after loading the host-local override.
