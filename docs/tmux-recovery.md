# Tmux topology recovery

Recovery is a public engine with private runtime state and optional provider
data. Both installation and scheduling are off by default. The downstream host
with 126 existing checkpoints and a scheduler opts in with
`tmuxRecovery.enable = true`; standalone public profiles remain off. It never
reads agent databases, captures scrollback or records arbitrary foreground commands.

```sh
tmux-recovery checkpoint --session project
tmux-recovery checkpoint-all
tmux-recovery restore /path/to/checkpoint.json
tmux-recovery restore /path/to/checkpoint.json --apply
tmux-recovery restore /path/to/checkpoint.json --prefix recovered- --apply
```

Checkpoint-all produces one consistent file containing all sessions; capture
failure leaves the previous checkpoint intact. Names are retained as JSON data
and hashed into fixed-length filenames for one-session snapshots. Files have a
version, ownership marker and payload checksum, are written atomically at mode
0600, and unchanged snapshots are reused without changing their mtime. No
legacy checkpoint is read, converted or removed automatically.

The default directory is `~/.local/state/tmux-agents-recovery`. Retention only
considers this engine's verified `public-tmux-v1-*.json` files: keep at most 32
globally and discard history older than seven days. The current snapshot is
protected even when unchanged beyond that age, within the same count cap. Bad,
unknown, symlinked and legacy files are outside the collector's ownership.

## Restore contract

Default restore prints a plan. `--apply` creates **new detached sessions** using
the original names (or an explicit prefix). It refuses collisions and missing
working directories before creation. It preserves window indices/names, layout,
pane order/cwd, active window/pane, title, label, provider options and optional
document path. Restored sessions disable automatic window renumbering to keep
saved index gaps. Existing clients are never selected or switched.

Panes initially show a parked recovery prompt so shell startup hooks cannot
erase restored identity. Press Enter to start the default shell, or explicitly
use `--apply --resume-agents` to resume providers. Normal provider hooks then own
their current labels. `--apply --resume-documents` opens stored documents with
`nvim -- <path>`; the path is data, never command text. Both modes in a pane with
both agent and document metadata are rejected as ambiguous. `new-human-req-doc`
records the pane-scoped `@recovery_document` path automatically.

If construction or resume fails, new partial sessions remain available for
inspection. There is no destructive rollback and no existing session is deleted.
Restored windows retain exited panes, so a failed provider launch remains visible.
The engine replaces only its own newly-created parked processes during explicit
resume. Restore is not a replay of the old terminal workload.

## Trusted provider adapters

Built-ins use `claude --resume <id>` and `codex resume <id>`, without approval or
sandbox bypass flags. `--adapters /path/to/adapters.json` or `.toml` loads a local
map, allowing overrides of built-ins and additional providers:

```json
{"codex":{"option":"@codex_sid","argv":["custom-cli","resume","{session_id}"]}}
```

Equivalent TOML:

```toml
[adapters.codex]
option = "@codex_sid"
argv = ["custom-cli", "resume", "{session_id}"]
```

Provider/option names and IDs are validated. `{session_id}` must be exactly one
separate argv element. Checkpoints contain IDs and option names, not adapter
argv, credentials or provider settings. Restore requires the trusted map to
match recorded options. Resume argv is shell-quoted for the configured shell,
so normal shell launch adapters work; no shell text is taken from checkpoints.
Private providers and wrapper commands belong only in downstream data.

## Home Manager

```nix
xj.publicDotfiles.tmuxRecovery = {
  enable = true;
  schedule.enable = true;
  schedule.interval = 300;
  keepNewest = 32;
  keepDays = 7;
  # outputDirectory and adaptersFile may be set by the private host.
};
```

The launchd job invokes the installed `~/.local/bin/tmux-recovery checkpoint-all`
with a private umask. Disabling the engine removes its package, home link and
job, even if the scheduling option remains true. It does not delete saved state.
Changing Git branches never activates or enables scheduling by itself.
