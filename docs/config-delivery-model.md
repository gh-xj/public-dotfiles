# Config Delivery Model

`public-dotfiles` has two configuration delivery kinds:

| Kind | Use for | Helper |
| --- | --- | --- |
| Live repo link | Every hand-edited config; repo edits take effect without evaluation or apply | `mkRepoFile`, `mkRepoTree` |
| Writable settings | App-written files; declared JSON keys are re-merged each apply, other seeds are written once | `mkMergedSettingsActivation`, `mkMutableSeedActivation` |

Generated artifacts are not a third config kind. They are limited to derived
data, executable/package links, and small, clearly named stubs carrying Nix
store paths or composed option values. A generated stub includes or sources a
live repo file for all hand-edited settings.

## Placement Rules

1. Use writable settings only when the app must write trust, session, auth, or
   runtime state into the target; prefer the merge helper for JSON.
2. Use a live repo link for every other hand-edited config.
3. Keep generated artifacts minimal and never copy hand-edited config into them.

## tmux Server Providers

Home Manager generates a PATH prelude before its base configuration and plugin
initializers. Bash, tmux, and the same generation's `home.path/bin` precede the
existing Brew/system fallback, including for GUI-started servers and plugins.

After activation, source `~/.tmux.conf` to update an existing server. Later
edits to the repository's `.tmux.conf` need only another source; no apply is
required. Reloading does not rewrite existing pane or per-session environments.

## Mutable Activation Ownership

Mutable agent links detach before old-generation cleanup; any set `DRY_RUN`
leaves them intact. Explicit seed opt-outs and downstream `home.file` ownership
win, and unproven foreign links are untouched. Ghostty's parent directory is
checked before link collision handling.
