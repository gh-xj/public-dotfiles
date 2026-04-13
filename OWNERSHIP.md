# Ownership

`public-dotfiles` owns the public, reusable live configuration paths under
`$HOME`.

What this repo owns:

- shell startup and prompt configuration that is safe to publish
- terminal and editor defaults that are meant to be reused across machines
- public-safe Claude/Codex policy, hooks, and baseline defaults
- other public, durable config that does not depend on private account state

What this repo does not own:

- private account state, secrets, or machine-specific auth material
- private agent runtime state, personal skills, or account-local overlays
- any path whose live owner is `private-config`

Representative live paths:

- `$HOME/.zshrc`
- `$HOME/.tmux.conf`
- `$HOME/.claude/settings.json`
- `$HOME/.codex/config.toml`
- `$HOME/.config/karabiner`
- `$HOME/.config/nvim`
- `$HOME/.config/zed`

Rules:

- each live path has exactly one owner
- `public-dotfiles` owns public reusable config
- `private-config` owns private durable state
