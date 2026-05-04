# Agent Rules

## Scope

This repository owns the public, reusable dotfile baseline. Keep private
machine state, credentials, account-local provider settings, sessions, caches,
and personal archives in `private-config`.

Use the `config-manager` skill for app configuration work. Edit source files in
this repo, not the live symlinks under `$HOME`.

## Commit Discipline

- Treat `public-dotfiles` and `private-config` as separate repositories with
  separate commits and pushes.
- Start every git operation with `git status --short` in the target repo. Notice
  unrelated dirty files and leave them unstaged.
- Stage explicit paths only: `git add -- path/to/file ...`. Do not use broad
  staging commands for dotfiles work.
- Inspect `git diff --cached` before committing.
- Keep each commit atomic: one behavior, policy, package ledger update, or doc
  update. Before staging, write the operation boundary in one sentence; if a
  second concern appears, split it into a separate commit.
- Treat an accepted atomic operation as incomplete until its intended changes
  are committed in the owning repo, unless the user explicitly asks to defer the
  commit. If a commit cannot be made because the scope is ambiguous, checks
  fail, or unrelated dirty files overlap the same paths, stop and report the
  blocker instead of silently leaving completed work uncommitted.
- If a final report includes uncommitted changes, name the exact reason. The
  reason this rule exists is that prior agent work sometimes stopped after
  editing and verification, while the written discipline only emphasized
  commit shape rather than requiring a commit for the completed operation.
- Treat each commit as an audit record. The final log for an operation must
  name the repo, commit hash, pushed branch, exact files staged, and
  verification commands run.
- Use imperative commit subjects that describe the behavior changed.
- Never amend, rebase, reset, checkout away, or force-push existing work unless
  the user explicitly asks for that operation.
- Keep `CLAUDE.md` as `@AGENTS.md` so Claude and Codex share the same commit
  discipline.

## Verification

- Run `task dotfiles:verify` before committing public dotfile changes.
- Run `task secrets:staged` before committing any change that touches scripts,
  agent config, shell config, tokens, URLs, headers, or generated config.
- If a check cannot run, state the exact command and failure reason in the final
  report.

## Daily Workflow

Read `docs/daily-git-workflow.md` for the normal branch, commit, verification,
and push path.
