# Ownership

This repo owns the public live configuration paths under `$HOME`.

Rules:

- each live path has exactly one owner
- `public-dotfiles` owns public reusable config
- `private-config` owns private durable state
- Mackup is not a live owner for any path managed here

Do not add paths here that are also owned by `private-config` or Mackup.
