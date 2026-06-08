# Config Delivery Model

`public-dotfiles` delivers public config to `$HOME` through three primary
classes. Choose the class first, then choose the file path.

| Class | Use For | Current Helper Surface |
| --- | --- | --- |
| Immutable link | Public config that should be replaced wholesale by Home Manager and does not need live app writes | `mkImmutableFile`, `mkImmutableTree` |
| Mutable seed | Public defaults that should initialize a writable runtime file once, then stay app-owned | `mkMutableSeedActivation` |
| Generated shim | Small generated files whose job is to bridge Home Manager output into another owned surface | `mkGeneratedText` |

Immutable links have two storage backends:

- Repo-backed live links: `mkRepoFile`, `mkRepoTree`
- Store-backed immutable links: `mkImmutableFile`, `mkImmutableTree`

Use repo-backed links only when the live app or workflow must see the checked-in
repo path itself, or when direct live editing of the repo-owned source path is
part of the intended workflow. Use store-backed immutable links by default.

## Placement Rules

1. If the target file must remain writable because the app persists trust,
   session, or runtime state there, use `mutable seed`.
2. If the target exists only to redirect or expose another owned surface, use
   `generated shim`.
3. Otherwise use `immutable link`.
4. For `immutable link`, prefer store-backed unless the live repo path is part
   of the user-facing contract.

## Current Examples

| Target | Class | Why |
| --- | --- | --- |
| `~/.codex/config.toml` | Mutable seed | Codex writes runtime trust and state after bootstrap |
| `~/.tmux.conf` | Generated shim | Bridges into Home Manager's generated tmux config |
| `~/.config/raycast/scripts` | Repo-backed immutable link | Raycast setup needs the durable repo path for UI registration |
| `~/.config/bat` | Store-backed immutable link | Static public config with no live repo-path requirement |
