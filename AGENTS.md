# Agent Rules

## Scope

This public repo owns the public-safe, opinionated app, shell, editor, terminal,
CLI, and agent defaults needed to restore xj's comfortable environment.
Never add sensitive/account-bound/company-private/secret-adjacent state or
private identifiers such as employers, internal projects, private hosts/IPs,
emails, or user-specific absolute paths; those belong in `private-config`.

Public is independently consumed by another Mac without `private-config`, so
its example profile and `task apply` / `task check` must remain standalone.
Use the `config-manager` skill and edit repo sources, never live `$HOME` links.

## Git and Worktrees

Before git operations, run `git status --short`; preserve unrelated changes.
Treat public and private as separate repos and commits. Stage explicit paths
only, and inspect `git diff --cached` immediately before every commit.
Stage new flake-consumed files before Nix checks because untracked files are
invisible to flake evaluation.

Only the lead session commits on `main`. Background agents use clean worktrees
on `agent/*`; the lead reviews and lands their atomic commits. Do not leave an
accepted operation uncommitted unless a reported blocker prevents it.
Keep `CLAUDE.md` as the one-line `@AGENTS.md` compatibility file.

## Verification

Run `task check` before commits; it includes the staged gitleaks scan and the
private-identifier denylist.
Report exact commands and failures. See `docs/daily-git-workflow.md` for the
normal branch, commit, verification, and push path.
