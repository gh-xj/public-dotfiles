# The SpaceFN hyper layer, and what it does not do

Holding space turns the alphabetic keys into a second layer. One of its rules,
`[SpaceFN] xj hyber keys combo`, rewrites a set of keys into a hyper chord -
`command + option + left_shift + <key>` - so that `space + d` arrives at the
system as `cmd+opt+shift+d`.

Karabiner stops there. It emits chords and never launches anything: the
delivered `karabiner.json` contains no `shell_command` at all. Every chord in
this layer therefore needs something else to receive it, and the receivers do
not all live in the same place.

## Two kinds of receiver, with very different durability

**Declared in this repo.** `.config/ghostty/config`, linked as
`~/.config/ghostty/user.conf`, binds one chord:

    keybind = global:cmd+shift+option+a=toggle_quick_terminal

That is a config file this repo delivers, so it works on any Mac the moment the
generation is activated.

**Not declared anywhere.** The rest are application-launch hotkeys assigned in a
launcher's own settings (Raycast, in this setup). Those assignments live in the
launcher's private store - for Raycast, local databases that are not readable as
SQLite - and are reachable only through its GUI. They are not in this repo, not
in a downstream overlay's manifest, and not in `defaults`:
`com.raycast.macos.plist` holds only the launcher's own global hotkey. Nothing
here can declare them; the only carrier is the launcher's own account sync
(`docs/bootstrap.md` lists Raycast Cloud Sync as a manual step), so a Mac where
that was never enabled starts with none of them.

The practical consequence on a fresh Mac is that the layer looks installed and
is mostly inert. Karabiner is healthy - permissions granted, driver loaded,
config loaded, rules present - and the chords are emitted correctly. They simply
land on nothing. One chord works, because one receiver is a declared file; the
others are silent, because their receivers were GUI state on the previous
machine. No check reports this, and no part of it is a fault.

`docs/bootstrap.md` and the bootstrap skill both record launcher registration as
a manual step. This document exists because "manual step" understates it: the
step is invisible until someone presses a key and nothing happens, and the key
that does work makes the layer look functional.

## Chords this layer currently emits

    space + a c d e g m n ' r t u v x y z   ->   cmd+opt+shift+<same key>

Fifteen chords. Which application each one should raise is a personal choice and
belongs with the machine's owner, not here - a downstream overlay is the right
place to record the mapping, so that rebuilding it after a migration is reading
rather than remembering.

## Telling the two halves apart

When a chord does nothing, decide which half is at fault before changing
anything. The first half is verifiable without guessing:

    # Is the chord even being emitted? Permissions are the usual suspect,
    # and the log states the answer outright rather than implying it.
    grep -i "permissions are granted" ~/.local/share/karabiner/log/core_service.log

    # Is the key in the layer, and is the profile that contains it selected?
    python3 - <<'PY'
    import json, pathlib
    d = json.loads(pathlib.Path("~/.config/karabiner/karabiner.json").expanduser().read_text())
    for p in d["profiles"]:
        rules = p.get("complex_modifications", {}).get("rules", [])
        print(p.get("name"), "selected" if p.get("selected") else "", len(rules), "rules")
    PY

If the chord is emitted and the profile is selected, Karabiner is not the
problem - the receiver is missing. Checking `space + a` first is the cheapest
test available: it is the one chord with a declared receiver, so if the quick
terminal appears, the whole Karabiner half is proven working end to end and the
remaining work is entirely in the launcher.

## Why it is worth writing down

A chord with a declared receiver and a chord with a GUI-assigned receiver are
indistinguishable from the keyboard, and both look identical in
`karabiner.json`. The layer's apparent health therefore says nothing about
whether it works, and the part that breaks on a new machine is the part no file
describes. Recording the intended mapping somewhere a new machine can read it
turns a silent loss into a few minutes of re-entry.
