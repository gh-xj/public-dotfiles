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

Git status uses the audited upstream plugin pinned in `package.toml`; the old
dual-version fetch adapter has been removed. The preview toggle keeps its
existing layout behavior with indexed ratios.

## Versions

Yazi and ya are owned by Nix at release 26.9.1, through a narrow package
override that leaves other nixpkgs packages pinned. The activated Home Manager
profile precedes Homebrew/system CLI paths, including after a home-only switch.
Both commands should resolve through the same activated profile and report
the same version. `task doctor` reports conflicting managed providers. Review
app and plugin updates together; CLI package changes need a new shell or rehash,
and a running Yazi instance needs restarting.
