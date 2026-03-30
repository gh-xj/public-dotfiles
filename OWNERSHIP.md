# Ownership

`public-dotfiles` owns the public, reusable live configuration paths under
`$HOME`.

What this repo owns:

- shell startup and prompt configuration that is safe to publish
- terminal and editor defaults that are meant to be reused across machines
- other public, durable config that does not depend on private account state

What this repo does not own:

- private account state, secrets, or machine-specific auth material
- private agent config or personal operational state
- any path whose live owner is `private-config`
- any path still managed by Mackup

Representative live paths:

- `$HOME/.zshrc`
- `$HOME/.tmux.conf`
- `$HOME/.config/karabiner`
- `$HOME/.config/nvim`
- `$HOME/.config/zed`

Rules:

- each live path has exactly one owner
- `public-dotfiles` owns public reusable config
- `private-config` owns private durable state
- Mackup is not a live owner for any path managed here
