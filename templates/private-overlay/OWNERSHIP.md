# Ownership

`private-config` owns private or machine-local live paths under `$HOME`.

Rules:

- each live path has exactly one owner
- `public-dotfiles` owns public reusable config
- this local-only `private-config` repo owns private durable state on this machine
- only paths listed in `private-paths.txt` are installed by this repo

Typical private paths include:

- `$HOME/.zshenv`
- `$HOME/.config/git`
- `$HOME/.ssh`
- `$HOME/.claude/skills`
- `$HOME/.agents/skills`
