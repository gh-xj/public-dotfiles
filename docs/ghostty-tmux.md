# Ghostty and tmux

## Upgrading the legacy Ghostty directory link

Older installs linked `~/.config/ghostty` to the checkout's `.config/ghostty`
directory. Native Home Manager Ghostty now owns only `~/.config/ghostty/config`;
its source of truth remains `programs.ghostty` in `modules/home/terminal.nix`.

Bootstrap preflight inspects the parent with link-aware semantics (including
dangling links). On apply, a known legacy link is logged and unlinked, its target
directory/content is preserved, and a real parent directory is created. Home
Manager then links the generated leaf. The same migration runs before
`checkLinkTargets` for direct Home Manager and downstream-overlay activations.
Repeating it leaves a real directory and its leaf unchanged. Dry-run logs the
planned action without modifying either location.

An unknown parent symlink or a `.config` ancestor resolving inside the checkout
stops activation. Inspect it and explicitly move it aside before retrying; the
normal Home Manager leaf-backup policy does not authorize replacing arbitrary
parent links. Do not recreate the standalone repo config. Any earlier accidental
generated leaf inside the checkout is left untouched for separate inspection.

After applying from the owning repo, verify the actual live delivery:

```sh
python3 scripts/verify-ghostty.py --live
```

The verifier requires a real parent, an existing leaf resolving to the current
Home Manager profile, successful `ghostty +validate-config`, and effective font,
theme, command and keybindings matching that generation. Use `--generation PATH`
for a nonstandard profile location, or `--ghostty PATH` for another executable.
It also detects overrides in other Ghostty config locations. `task check` runs
disposable upgrade fixtures using the generated Home Manager linker; it does
not activate or migrate your live home.

Existing Ghostty surfaces can retain startup settings. After a successful apply
and live check, reload Ghostty configuration and open a new surface to check its
startup command; CLI verification does not prove an already-open GUI surface
has reloaded. See [Ghostty config loading](https://ghostty.org/docs/config).

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
- Current window selectors are `Cmd+1..8 -> M-1..M-8`; both `Cmd+9 -> M-9` and the legacy `Cmd+0 -> M-0` select the highest-numbered window.

Current tmux prefix:

- `Ctrl-s`
- Prefix byte: `\x13`

Native Claude Code passthrough:

- Shared tmux config enables `allow-passthrough all` so Claude Code desktop notifications and progress updates can reach Ghostty even when the agent pane/window is not currently visible.
- Shared tmux config enables `extended-keys` plus `xterm*:extkeys` so Shift+Enter remains distinguishable from Enter inside tmux.
- Pane borders show the pane index, Workmux pane status, and agent label (or
  native terminal title). Bottom tabs retain the durable window name and status.

## Naming an agent workspace

Sessions group projects, windows identify durable work items, and panes identify
individual agents/conversations. Agents label only their own pane:

```sh
agent-pane-title set "Codex · investigate flaky tests"
agent-pane-title clear
```

Claude statusline consumes the official `session_name` and `agent.name` fields;
`/rename`, `--name`, and generated names propagate on the next statusline refresh
(also refreshed every five seconds). Missing fields restore the native title.
Codex SessionStart uses only documented hook fields to set a repository fallback.
No runtime database or transcript inspection is involved. SessionEnd and the
interactive zsh prompt clear labels. Unchanged labels do not call tmux.

Workmux is pinned to 0.1.248: `@workmux_pane_status` is an internal contract
covered by real working/waiting/done/clear tests. `@workmux_status` remains its
window summary (last update, not a count of pane states). PostToolUse restores
working after permission approval; subagent completion must not mark the parent
pane done. Native Codex subagents remain within its TUI.

Claude Agent Teams defaults to `in-process`. Anthropic documents split panes as
unsupported in Ghostty; no successful real Ghostty-inside-tmux team smoke test
has established otherwise. Use Workmux or manual panes for independent sessions.
Do not enable `auto` globally without that smoke test.

References: [Claude statusline](https://code.claude.com/docs/en/statusline),
[Agent Teams](https://code.claude.com/docs/en/agent-teams),
[Codex hooks](https://learn.chatgpt.com/docs/hooks).

Current pane shortcuts:

- `super+d` sends `prefix + |`: split active pane to the right and equalize pane sizes.
- `super+shift+d` sends `prefix + _`: split active pane downward and equalize pane sizes.
- `super+w` sends `prefix + X`: close the active pane immediately and equalize remaining pane sizes.
- `super+shift+enter` sends `prefix + z`: zoom or unzoom the active tmux pane.
- `super+ctrl+=` sends `prefix + E`: equalize the current tmux layout.
- `prefix + J` invokes EasyJump.
- `Ctrl-h/j/k/l` select tmux panes directly in root and copy-mode tables, even when the active pane is running nvim.
- `Ctrl-Left` / `Ctrl-Right` switch to the previous / next tmux window. Ghostty sends `prefix + p/n`; tmux also binds the native root keys for other terminal clients.

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
task check
```

This validates Ghostty config, Karabiner complex-modification assets, generated
tmux config loading, and the agent/Workmux pane integration.

## Theme policy

The shared tmux config uses an inline theme selector.

- Shared config sets `@theme` to `dark` by default.
- Optional host-local overrides belong in `~/.tmux.local.conf`, usually `set -g @theme light` or `set -g @theme dark`.
- The shared config applies the matching light or dark inline palette after loading the host-local override.
