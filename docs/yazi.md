# Yazi configuration

Yazi inherits its release defaults. The repo keeps personal overrides in
`.config/yazi`, delivered as an immutable Home Manager tree. Edit that source,
then verify and activate; do not run package updates against live config.

## Personal keys

| Keys | Action |
| --- | --- |
| `oo` / Enter | Open using file-type rules |
| `op` | Open selected files with the macOS default app |
| `oy` | Add selected files to Yoink |
| `b` | Open in Neovim in the current terminal; return when the editor exits |
| Ctrl-p | Quick Look in a detached window |
| `f` / Ctrl-f | Ordinary fuzzy jump / deep search including hidden and ignored files |
| `F` / Ctrl-t | Current-list filter / smart filter |
| `z` / `Z` | Directory history / fuzzy jump |
| Numbers | Vim-style counts, including `5j` and `2gt` |
| Left / Right | Previous / next tab |
| Up / Down | Scroll preview |
| F1–F5 | Switch to a tab, creating it if needed |
| `t` | New tab in the current directory |
| `Ps/Pl/PP/Pd/PD/Pm/PM` | Save/load/last/delete/delete-all/merge Projects |
| `Ud` | Move selection into the current directory's `Done/`; skip existing names |
| `w` / `~` | Task manager / Help |

`o` and `P` are command prefixes; single-key open and force-paste are shadowed.
The retained single `t` shadows upstream `tt/tr`; `gt` continues to open today.
File-list j/k stop at the boundary. Popup, input, completion and Help keys
inherit the selected release, including its newer editing and navigation keys.

SQLite files open a read-only schema view. Ordinary text uses `$EDITOR`;
archives and media keep the macOS application workflow. Special local rules
leave virtual-filesystem and trash handlers available. Directory previews keep
the existing depth-two tree and follow symlinks, including hidden entries.

## Plugin maintenance

Projects is a local fork: checked atomic persistence and malformed-state
protection must not be replaced by `ya pkg upgrade`. Its upstream revision and
local changes are documented in the vendored README. Other locked packages can
be updated in a writable config copy; review their source and `package.toml`
together before installing the result.

The existing toggle-view uses indexed ratios to support both current installed
versions. Replacing it with the current official toggle-pane requires a Yazi
release supporting that plugin's minimum-version annotation; coordinate that
with package ownership rather than breaking the declared baseline.

## Verification and versions

`task check` runs native isolated Yazi tests against the built generation.
Additional runtime versions can be checked explicitly:

```sh
python3 scripts/test-yazi-runtime.py /path/to/yazi
python3 scripts/test-yazi-projects.py /path/to/yazi
```

These checks exercise actual PTYs and disposable filesystem fixtures. They
validate argv quoting, task diagnostics, editor handoff, preview toggling,
non-overwriting Done moves, detached-window quit and Projects persistence.
A real macOS application open remains part of manual release validation.

The declared Nix baseline and an existing Homebrew installation can currently
provide different versions. This maintenance pass supports both 26.5.6 and
26.9.1. Package ownership should be unified separately; update `yazi` and `ya`
together and verify the chosen plugin/app combination. Do not remove one
installation before confirming the version that will take over.
