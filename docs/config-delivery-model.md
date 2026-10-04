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
| `~/.claude/settings.json` | Mutable seed | Claude writes plugin/account/runtime state after bootstrap |
| `~/Taskfile.yml` | Generated shim | Includes common tasks and the configured native operator owner |
| `~/.tmux.conf` | Generated shim | Bridges into Home Manager's generated tmux config |
| `~/.config/raycast/scripts` | Repo-backed immutable link | Raycast setup needs the durable repo path for UI registration |
| `~/.config/bat` | Store-backed immutable link | Static public config with no live repo-path requirement |

## tmux Server Providers

Home Manager generates a PATH prelude before its base configuration and plugin
initializers. Bash, tmux, and the same generation's `home.path/bin` precede the
existing Brew/system fallback. This covers a fresh server started by a GUI and
server `run-shell` commands without depending on an interactive shell startup.
The fzf URL plugin's unused `/tmp/filter` debug write is removed at build time.

After activation, source the generated `~/.tmux.conf` to update an existing
server. Reloading does not rewrite environments in existing panes or explicit
per-session PATH overrides; those need their own intentional refresh. Merely
editing the repository's `.tmux.conf` does not install the generated prelude.

## Mutable Activation Ownership

Mutable agent links are detached after Home Manager's `writeBoundary` and before
`linkGeneration` cleans the old generation. Any set `DRY_RUN` value, including an
empty value, leaves links intact. Disabling a public feature preserves legacy
bytes only when the target resolves to a known public source or the old public
generation declares that exact target. An enabled downstream `home.file` target
always takes precedence when its public seed is disabled; unproven foreign links
are left to their owner. Ghostty's parent directory is checked read-only before
link collision checks: resolve parent symlink ownership before activation.
