# Ownership

`public-dotfiles` owns the public-safe live configuration paths under `$HOME`.
Its job is to restore the non-sensitive parts of xj's comfortable operating
environment, not to provide a minimal or teaching-only baseline.

What this repo owns:

- shell startup and prompt configuration that is safe to publish
- terminal and editor defaults that are meant to be reused across machines
- public-safe CLI, GUI app, and package ledgers that shape daily ergonomics
- public-safe Claude/Codex policy, hooks, and baseline defaults
- public-safe project-local skills that operate this repo's bootstrap harness
- other public, durable config that does not depend on private account state

What this repo does not own:

- private account state, secrets, or machine-specific auth material
- company/private, account-bound, or secret-adjacent config
- runtime state, sessions, caches, generated state, or personal archives
- private agent runtime state, personal skills, or account-local overlays
- any path whose live owner is `private-config`

Representative live paths:

- `$HOME/.zshrc`
- `$HOME/Taskfile.yml`
- `$HOME/.tmux.conf`
- `$HOME/.claude/settings.json`
- `$HOME/.codex/AGENTS.md`
- `$HOME/.codex/rules/default.rules`
- `$HOME/.config/karabiner`
- `$HOME/.config/nvim`
- `$HOME/.config/zed`

Rules:

- each live path has exactly one owner
- `public-dotfiles` owns public-safe comfort config, even when it is opinionated
- `private-config` owns sensitive, account-bound, private, and runtime-adjacent durable state
- `$HOME/.codex/config.toml` is seeded from the public template only when
  missing; the live file stays mutable because Codex writes project trust and
  other runtime state there
