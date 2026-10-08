# Daily dotfiles operations

Use one configured owner from any working directory:

```sh
task -g dotfiles:doctor
task -g dotfiles:plan
task -g dotfiles:apply
task -g dotfiles:apps
```

The generated home Taskfile includes common tasks plus the owner's Taskfile.
A standalone public profile owns itself by default. A downstream profile sets
`xj.publicDotfiles.operationsTaskfile` once to its native Taskfile. The Task
include supplies the owning directory; it does not infer a private profile or
execute a second activation framework. `task apply` runs the standalone Home
Manager switch.

## Read the plan before applying

`plan` builds without activation or sudo. It summarizes managed home entries,
package source/version drift, and app reloads. It does not simulate arbitrary
activation hooks or promise that GUI caches have reloaded. `--json` emits one
machine-readable report.

The standalone bootstrap plans its working tree. Composed owners can choose a
stricter source policy; the private owner uses committed public/private HEADs.
The plan prints that policy and warns about pending edits. Hand-edited config is
repo-linked and can already reflect edits; generated artifacts still follow the
selected committed source.

`apply` activates the owning Home Manager generation and user-level macOS
settings without sudo. `apps` applies the Brewfile without cleanup and installs
the locked mise toolset. The public `Brewfile` is the baseline every Mac needs;
each entry names its public consumer or baseline role, and check rejects taps
and App Store apps there. An overlay keeps personal or work apps in its own
ledger and passes it as `task --dir <public> apps EXTRA_BREWFILE=<file>` (same
for `doctor`, which checks both ledgers and audits their formulae). Rebuilds do not update lock files;
dependency updates are a separate reviewed change. The configured owner retains
responsibility for its host selection and private data.

## Workstation state

`retention.enable` (off by default) schedules `workstation-retention`: it caps
launchd logs in place, archives old Codex/Claude transcripts per day as verified
`tar.zst` (resume of an archived session needs extraction first), and expires
Claude scratch. Scheduled runs only report until `retention.apply = true`;
downstream data adds `logs.globs`, `archives.<n>`, `scratch.<n>`. A downstream
`scratchGc` package replaces the scratch pass.

`encryptedMirrors.<name>` (`repository`, `remote`, `gpgKey` from downstream)
installs `encrypted-mirror-<name>` and a daily launchd push of commits only,
encrypted by git-remote-gcrypt. It pushes only when gpg-agent already holds the
key and never prompts (`--pinentry-mode=error`), otherwise it notifies. Restore
drill: `encrypted-mirror-<name> drill` clones the mirror and compares every
branch/tag SHA and the HEAD file count.

`task doctor` shows `jobs` (last retention run, mirror push and drill: ok, failed
or stale) and `recovery` (checkpoint verification). `recovery.nix` is the
topology engine; `retention.nix` only bounds disk growth.

## Check what actually runs

The active provider order is user-local tools, mise shims, the standalone Home
Manager profile, Determinate Nix, Homebrew, then macOS. Login and non-login zsh
use the same PATH; language runtimes do not leak in from ecosystem-specific
global bin directories.

`doctor` compares the live home with its active generation, checks macOS and
Brewfile drift, and audits every command declared by Home Manager, Brewfile, or
mise. Missing, duplicate or wrongly owned managed providers are failures; doctor
reports them without installing, removing, or activating anything.

After a package change, start a new shell or `rehash`; restart running programs
that still hold old code. For app configuration, follow the plan's reload
suggestions. Mutable agent settings remain app-owned and need explicit merge
review; they are not overwritten to make a plan look clean.

## Local entrypoints and checks

The same task names work in either owning repo. Public standalone bootstrap
retains its guard against applying over an adjacent composed private profile.
On an already configured machine, prefer the global owner rather than trying
to bootstrap another profile.

`task check` is the only verification surface. Plan and doctor are read-only;
they answer generation-change and live-drift questions respectively.
