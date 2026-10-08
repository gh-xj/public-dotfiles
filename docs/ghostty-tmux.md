# Ghostty and tmux

Home Manager owns a minimal `~/.config/ghostty/config` stub for the Nix tmux
path. Hand-edited settings live in `.config/ghostty/config` in this repo and are
linked as `~/.config/ghostty/user.conf`. The parent must already be a real
directory. Reload Ghostty after edits; open a new surface for startup settings.

This setup treats tmux as the primary terminal workspace layer and Ghostty as a keybinding bridge on macOS.

## Source of truth

- tmux custom config source: `~/public-dotfiles/.tmux.conf`
- tmux Home Manager module and plugin declarations: `~/public-dotfiles/modules/home/terminal.nix`
- Cmd+digit window selectors: generated in `~/public-dotfiles/modules/home/terminal.nix`
- live tmux custom config: `~/.config/tmux/user.conf` links to the repo
- generated tmux config: Home Manager renders `~/.config/tmux/tmux.conf`
- compatibility bridge: Home Manager renders `~/.tmux.conf` to source the live tmux config
- Ghostty config source: `~/public-dotfiles/.config/ghostty/config`
- live Ghostty custom config: `~/.config/ghostty/user.conf` links to the repo
- generated Ghostty stub: `~/.config/ghostty/config`

Do not create a second standalone Ghostty config file outside Home Manager.
Do not install TPM-managed tmux plugins by hand; public tmux plugins are
declared in Nix.

## Coupling rules

Ghostty sends raw bytes into tmux for a subset of shortcuts.

- Prefix-backed tmux shortcuts must use the current tmux prefix byte in Ghostty `text:\x..` mappings.
- Option/Alt is reserved for shells and terminal applications. The tmux root table binds no `M-*` keys, so fzf Alt-C, zsh word motions, and LazyVim Alt-j/k all reach the pane.
- Prefer Cmd/Super in Ghostty for tmux commands, and have those mappings send prefix-backed tmux commands.
- Do not install `vim-tmux-navigator` or a local Neovim/tmux navigation bridge. Tmux owns `Ctrl-h/j/k/l`; Neovim splits use native `Ctrl-w h/j/k/l`.
- Do not rewrite physical `Ctrl-h` / `Ctrl-l` in Karabiner. They must reach tmux as real control keys.
- EasyJump is allowed only on `prefix + J`; its copy-mode `Ctrl-J` binding is unbound so it cannot compete with pane navigation.

Window selectors:

- `Cmd+1..8` select that window; `Cmd+9` and `Cmd+0` select the highest-numbered one.
- Ghostty sends private `CSI 90<digit> ~` sequences that tmux claims as `user-keys` (prefix+digit picks a layout).

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
(event-driven, with no periodic polling by default). Identity precedence is:

```text
explicit Claude name / native AI title
    > agent-specific label
    > temporary repo fallback
    > native tmux pane title
```

Claude's native AI-generated first-prompt title is the semantic naming engine.
SessionStart sets only `@agent_label` to `Claude · <repo-or-cwd-basename>`;
nameless statusline updates leave it intact. Once `session_name` arrives it
replaces the fallback, optionally prefixed with `Claude/<agent.name>`.
Agent-only payloads show `Claude/<agent.name>`. Explicit names, generated titles,
and accepted-plan titles all use this same official field.
`SessionStart.sessionTitle` is appropriate only when the desired Claude name is
already known at launch: it acts like `/rename`, so this baseline never sets it.
`@agent_label` remains authoritative even if an application changes the native
pane title through OSC. Native titles are only a display fallback without a label.
Window naming belongs to durable work-item workflows such as `new-human-req-doc`,
not agent hooks. Lifecycle state stays separate and event-driven through hooks.
Claude and Codex SessionStart use only documented hook fields for repo fallbacks.
No runtime database or transcript inspection is involved. SessionEnd and the
interactive zsh prompt clear labels. SessionEnd requires a matching current
provider session ID; missing or stale IDs cannot clear a newer identity.
Unchanged labels do not call tmux.

Inside tmux, the zsh `codex` function passes the launching `TMUX` and `TMUX_PANE`
through per-invocation `shell_environment_policy.set` overrides. The shared
Codex app server may otherwise omit them from hooks and shell tools, making the
helper correctly no-op as though it were outside tmux. No pane IDs are persisted
in global config. The function also disables native Codex title updates in tmux
so Workmux sees the same agent-set title. Outside tmux it delegates unchanged to
the official standalone binary; direct binary invocations bypass this adapter.

After a hook definition changes, review and trust SessionStart/SessionEnd in
Codex `/hooks`. Trust is mutable runtime state and is never seeded or bypassed.
On an already-running tmux server, reload with `prefix + r` after activation;
otherwise the old border format can hide labels despite correct agent hooks.
New shell panes pick up the Codex function automatically; existing shells can
reload their `.zshrc` before starting another Codex session.

The environment override uses the official
[Codex command environment policy](https://learn.chatgpt.com/docs/config-file/config-advanced#shell-environment-policy).

Workmux is pinned to 0.1.248: `@workmux_pane_status` is an internal contract
covered by real working/waiting/done/clear tests. `@workmux_status` remains its
window summary (last update, not a count of pane states). `agent-workmux-status`
marks working on a prompt, waiting on a permission request, and done on Stop.
PostToolBatch (Codex: PostToolUse) restores working only after a permission
wait, even if the tool failed; ordinary tool results run one shell file test,
not tmux or Workmux, so Workmux processes never multiply by tool count. An interrupted turn can remain working until the next lifecycle
event; there is no polling loop to guess state. Private reporting hooks remain
downstream runtime state and are never removed by these public defaults.
Native Codex subagents remain within its TUI.

Claude statusline refresh is event-driven (including native naming changes).
For an idle clock or similar need, opt into `statusLine.refreshInterval = 30`
in the live settings. Existing mutable settings retain older intervals until
explicitly reviewed; the doctor flags periodic polling rather than changing it.

Claude Agent Teams defaults to `in-process`. Anthropic documents split panes as
unsupported in Ghostty; no successful real Ghostty-inside-tmux team smoke test
has established otherwise. Use Workmux or manual panes for independent sessions.
Do not enable `auto` globally without that smoke test.

References: [Claude statusline](https://code.claude.com/docs/en/statusline),
[session naming](https://code.claude.com/docs/en/sessions#name-your-sessions),
[Claude hooks](https://code.claude.com/docs/en/hooks),
[Agent Teams](https://code.claude.com/docs/en/agent-teams),
[Codex hooks](https://learn.chatgpt.com/docs/hooks).

Current pane shortcuts:

- `super+d` sends `prefix + |`: split active pane to the right and equalize pane sizes.
- `super+shift+d` sends `prefix + _`: split active pane downward and equalize pane sizes.
- `super+w` sends `prefix + X`: close the active pane and equalize the rest; `super+shift+t` (`prefix + T`) reopens the last closed pane in its window and cwd, resuming its Claude/Codex session.
- `super+shift+enter` sends `prefix + z`: zoom or unzoom the active tmux pane.
- `super+ctrl+=` sends `prefix + E`: equalize the current tmux layout.
- `prefix + J` invokes EasyJump.
- `Ctrl-h/j/k/l` select tmux panes directly in root and copy-mode tables, even when the active pane is running nvim.
- `super+shift+[` / `j` / `k` / `]` send `prefix + h/j/k/l` as the Cmd-hand alternative.
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

1. `programs.tmux.prefix` in `~/public-dotfiles/modules/home/terminal.nix`
2. Every Ghostty prefix-backed `text:\x..` mapping in `~/public-dotfiles/.config/ghostty/config`

After changing tmux prefix:

1. Reload tmux config
2. Reload or restart Ghostty

## Validation

Run this after changing Ghostty, tmux, or Karabiner terminal key rules:

```bash
task check
```

This validates the generated Home Manager configuration and its parseable
configuration files without inspecting live GUI state.

## Theme policy

tmux follows each client's reported light/dark theme (`client_theme`) live and
uses Ghostty's Atom One Light / One Dark Two colors. To pin one theme on a Mac,
put `set -g @theme light` or `dark` in `~/.tmux.local.conf`.
