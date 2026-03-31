# Ghostty and tmux

This setup treats tmux as the primary terminal workspace layer and Ghostty as a keybinding bridge on macOS.

## Source of truth

- tmux config: `/Users/xj/public-dotfiles/.tmux.conf`
- Ghostty config directory: `/Users/xj/public-dotfiles/.config/ghostty`
- Live Ghostty path: `~/.config/ghostty` -> `/Users/xj/public-dotfiles/.config/ghostty`

Do not create a second standalone Ghostty config file outside the tracked directory.

## Coupling rules

Ghostty sends raw bytes into tmux for a subset of shortcuts.

- Prefix-backed tmux shortcuts must use the current tmux prefix byte in Ghostty `text:\x..` mappings.
- Meta-backed tmux shortcuts should stay on `\x1b...` and do not change when tmux prefix changes.

Current tmux prefix:

- `Ctrl-s`
- Prefix byte: `\x13`

Examples:

- `super+t=text:\x13c` means Ghostty sends `prefix c` to tmux.
- `super+d=text:\x1bd` means Ghostty sends `Alt-d` to tmux and does not depend on tmux prefix.

## When changing tmux prefix

If tmux prefix changes, update both:

1. `set -g prefix ...` and `bind ... send-prefix` in `/Users/xj/public-dotfiles/.tmux.conf`
2. Every Ghostty prefix-backed `text:\x..` mapping in `/Users/xj/public-dotfiles/.config/ghostty/config`

After changing tmux prefix:

1. Reload tmux config
2. Reload or restart Ghostty

## Theme policy

The shared tmux config uses a static Catppuccin theme.

- Shared config sets the default flavor and loads Catppuccin directly.
- Optional host-local overrides belong in `~/.tmux.local.conf`.
- Local overrides are sourced before Catppuccin is rendered so they can override flavor cleanly.
