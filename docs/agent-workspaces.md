# Agent workspaces and recovery

Use a clean Git worktree for concurrent changes. Keep durable work in Git and
review explicit paths before commits. The requested `github.com/gh-xj/wt`
repository was not publicly retrievable (HTTP 404 at implementation time), so
the public baseline does not install it or require its commands. Until a public
release is available, use `git worktree add`, `git worktree list`, and
`git worktree remove` after reviewing uncommitted work.

## Scratch

`scratch-gc new investigation --purpose "reproduce parser behavior" --ttl-hours 24`
creates a private directory under `$XDG_CACHE_HOME/agent-scratch` (default
`~/.cache/agent-scratch`) with a versioned manifest. Namespace identifies the
kind of work; purpose explains ownership; TTL defaults to 24 hours, maximum 30
days. Do not use scratch for durable evidence, credentials or the only copy of
work. Keep company evidence protocols in downstream policy.

`scratch-gc ls` reports logical bytes and allocated block estimates. On APFS,
clones, compression and snapshots mean neither value proves reclaimable space.
Measure volume free space separately before/after an intentional final purge.

`scratch-gc collect` is a dry run. `collect --apply` moves expired manifest-owned
directories into `.quarantine` on the same filesystem. Unmanaged directories,
symlink entries and malformed manifests are skipped. Restore by moving the
reported `recover_from` directory back to its original path. There is no
automatic permanent purge or broad recursive deletion command.

## Tmux recovery

```sh
tmux-recovery checkpoint --session project ~/.local/state/tmux-recovery/project.json
tmux-recovery restore ~/.local/state/tmux-recovery/project.json
tmux-recovery restore ~/.local/state/tmux-recovery/project.json --apply
```

The engine saves window names, pane working directories, layout, focus and
documented hook-captured session IDs. Checkpoints are mode 0600 runtime state;
never commit them. It does not capture scrollback, databases, tokens or arbitrary
foreground commands. Restore defaults to a plan; `--apply` creates a new detached
`recovered-<session>` and refuses name collisions or unavailable directories.
For large layouts, resize the new window if its current terminal size is too
small to reproduce the saved layout. A failure leaves the new session visible
for inspection; it never rolls back by deleting existing work.

`--resume-agents` explicitly launches `claude --resume <id>` or
`codex resume <id>` in restored panes with normal permission behavior. Without
it, panes start as ordinary shells. Resume IDs are cleared on shell return.
Authentication and permission prompts remain owned by the CLI. Restore cannot
prove a historical session still exists in a provider's runtime.

Downstream overlays can supply `--adapters ~/.config/tmux-recovery/adapters.json`:

```json
{"custom": {"option": "@custom_sid", "argv": ["custom-agent", "resume", "{session_id}"]}}
```

Adapters are trusted local configuration, not checkpoint-supplied commands.
Their argv is shell-quoted and session IDs are validated; `{session_id}` must be
a separate argument. Public defaults never add approval or sandbox bypass flags.
Custom session IDs must be set/cleared by that provider's hooks or shell adapter.
Scheduling is intentionally opt-in: a downstream launchd job may invoke the
explicit checkpoint command for a chosen session; no global polling job is
installed automatically.

## Acceptance limits

Pane/rename behavior is verified with documented Claude statusline fixtures and
real tmux/Workmux. A live authenticated Claude `/rename` GUI session and Ghostty
Agent Teams split-pane smoke test are not automated; Teams remains in-process.
Destructive Codex prefix rules are not installed: static parsing cannot prove
their enforcement with approval policy `never`. Add them only after a runtime
test proves both prompt and forbidden decisions in that mode.
