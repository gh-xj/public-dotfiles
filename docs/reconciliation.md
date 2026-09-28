# Source, generation and running state

No Git hook invokes Home Manager or reconcile. Existing repo-linked editable
files still reflect source edits; this release detaches legacy agent-config
links on the first explicit apply. Until that migration, those old links retain
their existing source coupling. Regular mutable agent files are never merged
by a Git update or reconcile.
The explicit control plane is:

```sh
task doctor
task doctor -- --live
task doctor -- --live --flake /path/to/owning-flake#home-profile
task reconcile -- --dry-run --flake /path/to/owning-flake#home-profile
task reconcile -- --apply --flake /path/to/owning-flake#home-profile
```

Go-task forwards flags after `--`. Set `PUBLIC_DOTFILES_HOME_FLAKE` in your
optional private environment to avoid repeating `--flake`. It is never guessed
from an adjacent private repository. For a standalone public installation,
first prepare its host with `./scripts/bootstrap-macos.sh --dry-run --skip-build`,
then use the exact commands:

```sh
task reconcile -- --dry-run --flake "$HOME/.local/state/public-dotfiles/bootstrap/$USER#bootstrap"
task reconcile -- --apply --flake "$HOME/.local/state/public-dotfiles/bootstrap/$USER#bootstrap"
```

For an overlay, select that overlay's `homeConfigurations` profile instead.
Reconcile refuses another user's/home's profile and refuses any selected
generation that still declares mutable agent files as managed links. Selection
and builds do not update a flake lock file. Pin updates remain an explicit source
operation in the owning repository.

## Doctor

Without `--live`, doctor reports the checkout and origin/main revisions, dirtiness,
active generation, and selected generation when a flake is provided. Selection
evaluates the current profile but does not build it. `desired_built=false` means
there is no current build to inspect yet. Old generations without source metadata
report unknown, not a fabricated match. Public Git inputs carry a revision;
path inputs may be unversioned, so their source fingerprint and generation
comparison are the reliable evidence. The generation includes no account data.

`--live` adds Ghostty parent/leaf/validation checks, tmux pane-border and binary
version drift, mutable integration merge plans, generated-link health and disk
free space. No config files, hook bodies, process argv, project/pane names or
home paths are printed. Known public integration commands are the only command
bodies shown. Unknown managed target names are represented by stable hash IDs.
Standard Nix generation paths are shown; nonstandard paths are redacted.

Doctor does not start a tmux server or call Ghostty when a missing config could
cause Ghostty to create a template. CLI config validation does not prove old
Ghostty GUI surfaces have reloaded. A tmux version difference recommends manual
restart; it never kills a server. Generated-link traversal is bounded and reports
truncation rather than claiming a complete result. Each native observation has
a timeout. Override a nonstandard active profile with
`PUBLIC_DOTFILES_ACTIVE_PROFILE`; it is not printed verbatim.

## Reconcile

Dry-run may build the selected generation in the Nix store; it does not mutate
the live home, detach links, invoke activation, or reload tmux. It prints the
ordered wrapper actions, desired generation, owned-link additions/replacements/
removals, missing seeds, byte-preserving migrations, and manual follow-ups. The
selected profile's own package/service/activation code is delegated to Home
Manager, not executed or treated as safely simulatable during dry-run. Choose a
profile whose declarations you have reviewed. An unchanged, healthy generation
with matching tmux state produces an empty operation list.

Apply executes that same operation list: the tested Ghostty parent migration,
managed mutable-link detachment, selected generation activation, and tmux reload
from the new live `~/.tmux.conf`. It does not run nix-darwin, start/restart Ghostty,
terminate agents or panes, stop containers/security software, or merge settings.
Ghostty command changes are reported as requiring config reload and a new
surface or manual restart. It cannot make startup-only settings retroactive.

Activation failures stop the sequence before tmux reload. Reconcile suppresses
untrusted subprocess output; use the selected profile's native activation
command locally when investigating its error. No rollback deletes work.

## Mutable agent integration

Claude settings, Codex config and Codex hooks are all mutable seeds. Before Home
Manager cleans old links, known managed file symlinks are detached into mode-0600
files with the same bytes. Regular files and unknown external links are not
overwritten. Parent directory symlinks require explicit ownership resolution.
Missing files are seeded after normal linking. Downstream overlays must stop
declaring these runtime files through `home.file` and keep their private entries
in the live writable files instead.

The live doctor produces a merge plan for missing `agent-session` start/end,
statusline and Workmux lifecycle entries, and flags old public per-tool commands
and periodic statusline refresh. Additional private hooks are accepted without
printing their bodies. Review and merge the listed public entries explicitly
using the app or your editor, preserving other entries and matcher scopes.
There is intentionally no automatic hook merge in reconcile. Codex `/hooks`
trust remains a separate native review step. Existing five-second statusline
refreshes are flagged for review; the new seed is event-driven, with 30-second
refresh available only as a user opt-in.

The doctor compares the public JSON integration contract. Private inline TOML
hooks and plugin-provided hooks remain outside that ownership; review them when
consolidating the plan to avoid adding a duplicate integration from another source.

## Bounded workspace health

```sh
agent-workspace doctor
task workspace:health
task workspace:health -- --warn-clients 8 --warn-agent-panes 32 --top 5
```

The installed command and task use the same read-only, single-snapshot engine.
It reports attached tmux clients (including the Ghostty subset), unique sessions,
windows and panes, agent-tagged panes, supported Claude/Codex CLI process counts,
tmux/Ghostty CPU, Workmux active/finished counts, disk free space and generation
drift. Shared Codex app-server processes are excluded from the CLI agent count;
process counts are not conversation counts. Pane identities can be stale when
a provider fails to run cleanup, so process counts are reported independently.

Default warnings trigger above 6 clients, 24 agent-tagged panes, 40 total panes,
or 90% Data-volume use. Search/build/test candidates older than 600 seconds with
at least 20% CPU are reported (at most 10, configurable up to 50). `ps` CPU values
are a snapshot, not a profiler. Only public workload categories and numeric PIDs
are shown, never executable paths, full argv, project names or unsupported
provider names. Custom Workmux icons are counted as unknown rather than exposed.

Threshold flags: `--warn-clients`, `--warn-agent-panes`, `--warn-panes`,
`--warn-disk-use`, `--warn-long-seconds`, `--warn-long-cpu`, and `--top`.
Unknown/unavailable observations are explicit gaps, not a healthy zero.

There is no Nix evaluation by default: generation source metadata is inspected
locally. Add `--flake /path/to/owning-flake#home-profile` to opt into comparison
with an evaluated current profile, or `--generation /nix/store/...` for an already
built comparison. Health never builds, activates, merges config, reloads a
server, terminates a process, or closes a pane. No launchd timer is installed.
