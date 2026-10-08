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

Neovim is LazyVim plus overrides. Leader is Space, localleader comma; leader
keys follow LazyVim. Zed Vim defaults already match `gd`, `gD`, `gy`, `gI`,
`gA`, `gh`, `g.`, `gs`, `gS`, `gl`, `gL`, `ga`, `]d`/`[d` and `]c`/`[c`.

| Keys | Both editors |
| --- | --- |
| `j` / `k`, `J` / `K` | Display-line movement; five display lines |
| `t` | Cursor line to top |
| Left / Right, Alt-h / Alt-l | Previous / next buffer or tab |
| F1–F9, F10 | Buffer/tab index; alternate file |
| Ctrl-p, `<Space><Space>`, `<Space>ff` | Find files |
| `<Space>,`, `<Space>/`, `<Space>sr` | Buffers/tabs, project search, search and replace |
| `<Space>cs`, `<Space>cr`, `<Space>cf`, `<Space>ca` | Outline, rename, format, code action |
| `<Space>gg`, `<Space>gd` | Lazygit; review Git diff |
| `<Space>e`, Ctrl-e | File tree sidebar; Yazi |
| `<Space>\|`, `<Space>-`, `]w` / `[w` | Split right/down; next/previous pane |

Zed's Cmd-1–8 select panes, retaining the historical macOS habit. Native Cmd
shortcuts and Vim Ctrl-w pane navigation remain available. The existing
Karabiner Ctrl-s → Ctrl-Tab rule still applies to Zed. Terminal Shift-Enter
sends the same sequence as Ghostty.

Both auto-save one second after an edit; Neovim also reloads clean buffers
changed on disk (warning on unsaved edits). Only Go (`gofmt`) and JSON (`jq`)
format on save.

## Deliberate differences

- tmux owns Ctrl-h/j/k/l and Ctrl-Space; Neovim uses Ctrl-w and Ctrl-n.
- F-keys select existing Zed tabs; Neovim creates an empty buffer when an
  indexed buffer does not exist.
- Neovim's EasyMotion `s`, Flash `f`/`F`/`T`/`S`, terminal pickers, Markdown
  rendering and `,`-prefixed Markdown helpers are not emulated by Zed's Vim
  layer. Zed retains its native `s` substitute.
- Zed Python uses Pyright plus Ruff, instead of the historical overlapping
  Pyright/PyLSP/Ruff stack. Project lint/type rules remain project-owned.

Review uncommitted changes with `git: diff` (split view). Zed's Git settings
also support changing the diff base; choose the correct base when reviewing
agent commits instead of assuming a clean working tree has no changes.
