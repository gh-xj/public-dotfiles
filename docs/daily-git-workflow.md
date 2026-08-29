# Daily Git Workflow

The canonical flow for routine work in `public-dotfiles` and `private-config`.
`private-config` keeps a short companion doc for the deltas that only apply
there; everything below is shared.

## Before Editing

1. Resolve ownership before changing config:
   - public-safe app, shell, editor, terminal, CLI, and agent defaults:
     `~/public-dotfiles`
   - private, machine-local, account-specific, or secret-bearing state:
     `~/private-config`
2. Inspect the worktree, and both worktrees when the task may cross the
   boundary:
   - `git -C ~/public-dotfiles status --short`
   - `git -C ~/private-config status --short`
3. If unrelated files are dirty, leave them alone and stage only the paths you
   intentionally changed.
4. Run git steps sequentially. Do not overlap `git add`, `git rm`,
   `git commit`, or adjacent git reads in parallel; transient `index.lock`
   races are easy to trigger in this workflow.

## Before Commit

1. Stage explicit paths only:
   `git add -- path/to/file ...`
2. If a new file is consumed by flake evaluation, stage it before any `nix` or
   `task` verification step. Untracked files are invisible to flake evaluation.
3. Inspect exactly what will be committed:
   `git diff --cached`
4. Run the central verification surface, including staged secret risk:
   `task check:full`
5. Commit one behavior at a time:
   `git commit -m "Set git init default branch to main"`
6. Do not leave an accepted atomic operation uncommitted by default. If the
   commit is deferred, the final report must say exactly why.

## Atomic Commit Split

Use separate commits when changes can be understood or reverted separately:

- package tracking versus app behavior
- public config versus private config
- agent policy versus implementation
- docs that describe an operator workflow versus code that implements it

Combining is acceptable only when splitting would leave one commit broken, such
as adding a config that directly requires a newly tracked binary.

An accepted atomic operation is complete only after the owning repo has a
commit for it, unless the user explicitly asked to stop before committing or a
blocker was reported. This closes the gap in the older rule text: it described
how to shape commits, but did not say that verified completed work must be
committed.

## After Commit

1. Confirm the hash:
   `git log -1 --oneline --decorate`
2. Push only the intended branch:
   `git push origin main`
3. Report the atomic operation with repo, hash, files, and checks.

## LazyGit Notes

Lazygit is fine for review and focused staging, but the same rule applies:
stage only the intended paths and keep unrelated dirty files out of the commit.
