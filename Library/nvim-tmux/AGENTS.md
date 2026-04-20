# Agents working on nvim-tmux

Read this before touching anything in `Library/nvim-tmux/`. It captures
the hard-won constraints that every previous attempt violated.

## What this is

A macOS URL handler. Clicking `nvim-tmux:///abs/path?session=X&window=Y`
lands an nvim pane at `tmux X:Y`, then raises Ghostty pointed at the
tab showing that session. That's the entire product. Not a CLI. Not a
general tool. Not a publishable library.

## Contract (the URL is the API)

```
nvim-tmux://<path>[?session=<session>&window=<window>]
```

Invariants:

- `<path>` is absolute, or begins `/~/` (expanded to `$HOME`).
- `session` and `window` are **both required**. Missing either →
  macOS notification + exit 2. Don't invent defaults.
- Window is matched by **name**, not index. Missing window → created
  (with `-n <window>`).
- Missing session → created (`new-session -d`).
- File already open in **that** session/window → reuse the pane.
  File open elsewhere → ignored; a new pane is spawned in the target.
  Cross-window reuse would require `join-pane`, which violates "user's
  other windows stay put."
- Navigation: always switch the **most-recently-active** tmux client
  (any session) to the target pane. Rationale: macOS raises the
  frontmost Ghostty window on `open -a Ghostty`, and that window's
  tmux client is the most-recently-active one. Yanking a different
  client defeats focus; yanking the most-recent one ensures the raised
  window shows the target.

## The hard rule

**Never spawn a new Ghostty window or instance programmatically.**
This is absolute. All of the following have been verified to corrupt
xj's multi-session tab layout with ghost clients attached to `main`:

- `open -na Ghostty.app --args …`
- `open -na Ghostty.app --args --command="tmux attach -t X"`
- `open -na Ghostty.app --args -e "tmux attach -t X"`
- `osascript`-driven cmd+n into the Ghostty process
- `tell application "Ghostty" to make new window` (fails, listed
  because someone will try)
- `/Applications/Ghostty.app/Contents/MacOS/ghostty +new-window`
  (unsupported on macOS)

Root cause: Ghostty restores prior tab/session state on new windows or
instances. Any `-e`/`--command` arg is applied unpredictably across
restored tabs. Two separate incidents produced identical damage.

If the target session has no attached client, the handler creates the
tmux state and calls `open -a Ghostty` (no `-n`, no `--args`). The
user either manually navigates, or accepts a notification. **This is
the design**, not a missing feature.

## Known pitfalls (do not relearn)

| Trap                                          | Symptom                                    | Fix                                                           |
| --------------------------------------------- | ------------------------------------------ | ------------------------------------------------------------- |
| `pgrep -x Ghostty` (capital G)                | "not running" on a running instance        | Process name is lowercase `ghostty` on macOS                  |
| `set -e` + `ps -t <tty>` no-match             | Silent function exit, wrong branch taken   | Don't use `set -e` around probing loops                       |
| `/tmp/foo.md` vs nvim's `/private/tmp/…`      | Reuse detector misses existing panes       | `filepath.EvalSymlinks` both sides                            |
| `tmux list-panes -t session:win.pane`         | Returns all panes, not just the targeted   | Iterate all and filter in code                                |
| `tmux new-window` without `-d`                | Clients on that session follow the new win | Use `-d` when creating (we only need to own the name)         |
| `tmux new-session` w/o `automatic-rename off` | Window names drift to command names        | Handler passes explicit `-n`; tmux honors it                  |
| Path with spaces in `ps -o args=` output      | Arg boundaries ambiguous — reuse fails     | Document, accept duplicate pane                               |
| `tmux switch-client -t session:win.pane`      | `-t` only accepts a session                | `switch-client` + `select-window` + `select-pane` in sequence |

## Dev workflow

```sh
# Edit main.go, then:
task nvim-tmux:build      # compiles bin/nvim-tmux
task nvim-tmux:install    # copies into ~/Applications/nvim-tmux.app

# End-to-end test without touching live sessions:
~/Applications/nvim-tmux.app/Contents/Resources/nvim-tmux \
  'nvim-tmux:///tmp/SCRATCH.md?session=nvim-tmux-test&window=doc'
tail -n 20 /tmp/nvim-tmux.log
tmux kill-session -t nvim-tmux-test   # cleanup
```

Prefer synthetic sessions when testing. Firing against `main` or any
attached session yanks the user's frontmost tab.

## Stack (locked)

Per `~/.claude/skills/go-scripting`, this is a **Script tier** tool:

- Single `main.go`, stdlib only.
- `stdlib slog` for logging; no third-party logger.
- No `kong` (would cost more LOC than the router is worth for a
  one-positional-arg binary).
- No `go-pretty`, no spinners (it's a URL handler, not a CLI).
- `darwin/arm64` only. No build tags, no cross-compile.

If you're tempted to add a dependency, re-read the skill.

## Non-goals

- Support for other terminal emulators. Ghostty is the contract.
- Support for other OS. macOS-only. `open`, `osascript`, and
  LaunchServices are load-bearing.
- Publishing to GitHub as a standalone tool. Personal infra.
- A configuration file. Everything is in the URL.
- Multi-file nvim invocations, quickfix integration, or line-number
  anchors. Out of scope until there's a concrete workflow need.

## Commit protocol

This repo uses the Lore trailer format defined in the repo-root
`.claude/CLAUDE.md`. When committing changes here:

- Intent line first — _why_, not _what_.
- `Tested:` / `Not-tested:` always, for code.
- `Rejected:` any alternative you considered, so the next agent
  doesn't waste a cycle.
- `Directive:` if you want to constrain future modifiers.
- Standard `Co-Authored-By:` trailer at the end.

## Where state lives

| Thing                                      | Path                                                                                           |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------- |
| Go source                                  | `Library/nvim-tmux/main.go`                                                                    |
| Prebuilt binary (committed)                | `Library/nvim-tmux/bin/nvim-tmux`                                                              |
| Thin shell shim (.app invokes this)        | `Library/nvim-tmux/handler.sh`                                                                 |
| Installed binary                           | `~/Applications/nvim-tmux.app/Contents/Resources/nvim-tmux`                                    |
| Runtime log (overwritten per fire)         | `/tmp/nvim-tmux.log`                                                                           |
| URL scheme registration                    | `~/Applications/nvim-tmux.app/Contents/Info.plist` → `CFBundleURLTypes`                        |
| Feedback memory enforcing the Ghostty rule | `~/.claude/projects/-Users-xj-public-dotfiles/memory/feedback-ghostty-new-window-forbidden.md` |
