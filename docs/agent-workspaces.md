# Agent workspaces and recovery

Use a clean Git worktree for concurrent changes. Keep durable work in Git and
review explicit paths before commits. The requested `github.com/gh-xj/wt`
repository was not publicly retrievable (HTTP 404 at implementation time), so
the public baseline does not install it or require its commands. Until a public
release is available, use `git worktree add`, `git worktree list`, and
`git worktree remove` after reviewing uncommitted work.

## Acceptance limits

Pane/rename behavior is verified with documented Claude statusline fixtures and
real tmux/Workmux. A live authenticated Claude `/rename` GUI session and Ghostty
Agent Teams split-pane smoke test are not automated; Teams remains in-process.
Destructive Codex prefix rules are not installed: static parsing cannot prove
their enforcement with approval policy `never`. Add them only after a runtime
test proves both prompt and forbidden decisions in that mode.
