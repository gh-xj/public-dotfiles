# Daily Git Workflow

Use this flow for routine work in `public-dotfiles`.

## Before Editing

1. Check scope: public-safe app and shell configuration belongs here; private
   state belongs in `private-config`.
2. Inspect the worktree:
   `git status --short`
3. If unrelated files are dirty, leave them alone and stage only the paths you
   intentionally changed.

## Before Commit

1. Stage explicit paths:
   `git add -- path/to/file ...`
2. Inspect exactly what will be committed:
   `git diff --cached`
3. Verify the repo, including staged secret risk:
   `task dotfiles:verify`
4. Commit one behavior at a time:
   `git commit -m "Improve lazygit workflow"`
5. Do not leave an accepted atomic operation uncommitted by default. If the
   commit is deferred, the final report must say exactly why.

## Atomic Completion

An accepted atomic operation is complete only after this repo has a commit for
it, unless the user explicitly asked to stop before committing or a blocker was
reported. This closes the gap in the previous rule text: it described how to
shape commits, but did not say that verified completed work must be committed.

## After Commit

1. Confirm the hash:
   `git log -1 --oneline --decorate`
2. Push only the current branch:
   `git push origin main`
3. Report the atomic operation with repo, hash, files, and checks.

## LazyGit Notes

Lazygit is fine for review and focused staging, but the same rule applies:
stage only the intended paths and keep unrelated dirty files out of the commit.
