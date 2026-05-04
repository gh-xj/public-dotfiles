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

## After Commit

1. Confirm the hash:
   `git log -1 --oneline --decorate`
2. Push only the current branch:
   `git push origin main`
3. Report the atomic operation with repo, hash, files, and checks.

## LazyGit Notes

Lazygit is fine for review and focused staging, but the same rule applies:
stage only the intended paths and keep unrelated dirty files out of the commit.
