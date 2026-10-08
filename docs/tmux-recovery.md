# Tmux topology recovery

Recovery is a public engine with private runtime state and optional provider
data. Both installation and scheduling are off by default. The downstream host
with 126 existing checkpoints and a scheduler opts in with
`tmuxRecovery.enable = true`; standalone public profiles remain off. It never
reads agent databases, captures scrollback or records arbitrary foreground commands.

One principle: a bad pane, session or directory never costs the rest.

```sh
tmux-recovery checkpoint-all                  # or: checkpoint --session NAME
tmux-recovery restore FILE [--apply] [--prefix recovered-]
tmux-recovery resume [--all] [--delay 5]      # start recorded agents/editors
tmux-recovery preflight [--bundle DIR]        # before a planned reboot
tmux-recovery orphans                         # processes that outlived their pane
tmux-recovery status                          # re-verify every stored checkpoint (exit 1 if corrupt)
```

Checkpoint-all is one consistent file of all sessions from a single
`list-panes -a` plus one `ps`; a failed capture leaves the previous checkpoint
intact. Odd data is dropped per pane with a warning (invalid ids, control
characters, unreadable layouts), never the checkpoint, and each run appends one
line to `recovery.log` in the state directory (counts, warnings, and busy
orphans). Files have a version, ownership marker and payload checksum, are
written atomically at mode 0600, and unchanged snapshots are reused. Existing
checkpoints stay restorable; no legacy file is read, converted or removed.

The default directory is `~/.local/state/tmux-agents-recovery`. Retention only
considers this engine's verified `public-tmux-v1-*.json` files: keep at most 32
globally and discard history older than seven days. The current snapshot is
protected within the same cap. Bad, unknown, symlinked and legacy files are
outside the collector's ownership.

Editors are found anywhere in a pane's process tree by asking the editor's own
server (nvim) for its file, so wrapper-launched editors are recorded as the
pane document; `@recovery_document` still wins when set. Agents are identified by
the pane option `@resume_target` (`<provider> <session_id>`) written by
`agent-session`, never by process name, and prompt hooks do not clear it.

## Restore contract

Default restore prints a plan. `--apply` works per session: an existing session
is skipped, a missing directory falls back to `~`, a session that fails is
reported and the next one still runs (exit status 1 if any failed). It creates
**new detached sessions** under the original names (or `--prefix`), preserving
window indices/names, layout, pane order/cwd, active window/pane, title, label
and resume target. Existing clients are never selected or switched, partial
sessions stay for inspection, and **nothing is started**: panes show a parked
prompt (Enter starts the default shell).

`resume` is the only thing that starts programs: in the current pane, or with
`--all` every pane staggered by `--delay` seconds so a reboot does not recreate
the overload. Only panes at a shell prompt (or still parked) are started; busy
panes are reported. A recorded agent resumes via its adapter, otherwise a
recorded document opens with `nvim -- <path>`.

`preflight` lists agents that look mid-task (live agent pane whose process tree
uses at least 5% CPU, an inference, not proof) and editors with unsaved buffers.
`--bundle DIR` adds a small `lag-*.txt` (uptime, memory pressure, vm_stat, top
processes). `orphans` reports processes with ppid 1 whose `TMUX` socket is this
server and whose `TMUX_PANE` no longer exists; it only reports (busy ones are
also noted in `recovery.log`), and killing stays with the human.

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
Private providers/wrappers belong in downstream data; Cmd+Shift+T reopen uses this map.
`agent-session <provider> start|end` accepts any provider name (`@<provider>_sid`); a start clears every other `*_sid` on the pane.

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
