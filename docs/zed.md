# Zed and Neovim

Zed is the graphical code-reading and review surface; Ghostty/tmux owns agent
workspaces, and Neovim remains `$EDITOR` for terminal edits. Zed can open the
same checkout or a sibling Git worktree without moving the agents.

## Sources and delivery

- Settings, keymap, tasks, snippets and theme: `.config/zed/` in this repo
- Home Manager: individual repo-backed links in `~/.config/zed/`
- App installation: `zed` in `Brewfile`
- CLI: Homebrew installs `zed`; use `zed path/to/worktree`

Leaf links let Zed retain its own mutable files and databases alongside public
configuration. Edit the repo sources to change the baseline. Credentials,
agent accounts, sessions, model/provider settings and prompt databases remain
app-owned or private; none are restored from historical public config.

History provenance: preferences, One theme and Markdown snippets were recovered
from the parent of `752843c` (2026-04-17 removal). Keyboard alignment follows
the current Neovim sources rather than the obsolete agent/config guide.
Three malformed white color values in the historical theme were normalized
to valid RGBA. `task check` validates the Zed JSON and theme colors.

## Shared editing habits

The leader is comma. Existing Zed Vim defaults already match Neovim's `gd`,
`gD`, `gy`, `gI`, `gA`, `gh`, `g.`, `gs`, `gS`, `gl`, `gL`, `ga`, `]d`/`[d`,
and `]c`/`[c`; they are not duplicated in the user keymap.

| Keys | Both editors |
| --- | --- |
| `j` / `k`, `J` / `K` | Display-line movement; five display lines |
| `t`, `,,` | Cursor line to top; center cursor |
| Left / Right, Alt-h / Alt-l | Previous / next buffer or tab |
| F1–F9, F10 | Buffer/tab index; alternate file |
| Ctrl-p, `,f` | Find files |
| `,b`, `,r`, `,c` | Buffers/tabs, project search, commands |
| `,o`, `,rn`, `,=` | Outline, rename symbol, format |
| `,gg`, Ctrl-e / `,e` | Lazygit; Yazi |
| `,gd` | Review Git diff |
| `,vs`, `,hs`, `]w` / `[w` | Split right/down; next/previous pane |

Zed's Cmd-1–8 select panes, retaining the historical macOS habit. Native Cmd
shortcuts and Vim Ctrl-w pane navigation remain available. The existing
Karabiner Ctrl-s → Ctrl-Tab rule still applies to Zed. Terminal Shift-Enter
sends the same sequence as Ghostty.

## Deliberate differences

- Zed auto-saves after one second, as in the historical profile; Neovim saves
  explicitly. Go (`gofmt`) and JSON (`jq`) format on save in both. Markdown and
  other languages format explicitly rather than rewriting prose during review.
- Zed's `,gf` is its normal file finder, not Snacks' tracked-files-only picker.
- F-keys select existing Zed tabs; Neovim creates an empty buffer when an
  indexed buffer does not exist.
- Neovim's EasyMotion `s`, terminal pickers and Markdown rendering plugins are
  not emulated by Zed's Vim layer. Zed retains its native `s` substitute.
- Zed Python uses Pyright plus Ruff, instead of the historical overlapping
  Pyright/PyLSP/Ruff stack. Project lint/type rules remain project-owned.

Review uncommitted changes with `git: diff` (split view). Zed's Git settings
also support changing the diff base; choose the correct base when reviewing
agent commits instead of assuming a clean working tree has no changes.
