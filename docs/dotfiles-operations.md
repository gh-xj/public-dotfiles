# Daily dotfiles operations

Use one configured owner from any working directory:

```sh
task -g dotfiles:doctor
task -g dotfiles:plan
task -g dotfiles:apply:home
task -g dotfiles:plan -- --system
task -g dotfiles:apply:system
```

The generated home Taskfile includes common tasks plus the owner's Taskfile.
A standalone public profile owns itself by default. A downstream profile sets
`xj.publicDotfiles.operationsTaskfile` once to its native Taskfile. The Task
include supplies the owning directory; it does not infer a private profile or
execute a second activation framework. Existing `task apply` remains an alias
for system scope because bootstrap and other callers still use it.

## Read the plan before applying

`plan` builds without activation or sudo. It summarizes managed home entries,
package source/version drift, and app reloads. `--system` additionally builds
the native system closure; the file/package summary still describes Home
Manager. It does not simulate arbitrary activation hooks or promise that GUI
caches have reloaded. `--json` emits one machine-readable report.

The standalone bootstrap plans its working tree. Composed owners can choose a
stricter source policy; the private owner uses committed public/private HEADs.
The plan prints that policy and warns about pending edits. Repository-backed
links may already reflect edits even when immutable snapshots use committed
sources. Keep those two effects distinct.

`apply:home` activates the owning Home Manager generation without sudo.
`apply:system` runs the native nix-darwin switch with sudo and includes its
Home Manager phase. Rebuilds do not update lock files; dependency updates are a
separate reviewed change. The configured owner retains responsibility for its
host selection and private data.

## Check what actually runs

The active Home Manager profile precedes Homebrew and system profiles for
ordinary declared CLI tools. User-local and project SDK bins keep precedence.
This makes a home-only package switch usable on nix-darwin hosts even before
the next system switch updates `/etc/profiles/per-user`.

The generation's existing public manifest records the Yazi/ya package version
from the installed derivation. Live doctor probes those two known commands and
compares their resolved binaries with the selected/active generation. It
reports unknown for missing observations, prints no arbitrary native stdout or
private paths, and never uninstalls competing packages. A same-version binary
from a different provider still counts as source drift.

After a package change, start a new shell or `rehash`; restart running programs
that still hold old code. For app configuration, follow the plan's reload
suggestions. Mutable agent settings remain app-owned and need explicit merge
review; they are not overwritten to make a plan look clean.

## Local entrypoints and checks

The same task names work in either owning repo. Public standalone bootstrap
retains its guard against applying over an adjacent composed private profile.
On an already configured machine, prefer the global owner rather than trying
to bootstrap another profile.

`task check` is the routine verification surface. `task check:deep` retains
slower runtime and cross-profile probes. Package/version migrations also run
native Yazi/Projects tests against the built binaries. Plan and doctor are
read-only; they are not substitutes for those checks.
