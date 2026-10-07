# macOS Settings

`config/macos/settings.json` is the public, user-level defaults ledger. It
syncs keyboard repeat, pointer and trackpad behavior, input sources, symbolic
hotkeys, Dock/menu bar/Mission Control/Stage Manager layout, desktop icons,
Finder, Raycast plain preferences, and Super Easy Timer.

Home Manager runs `macos-settings apply` during activation. Apply preserves
plist types, merges symbolic hotkeys one ID at a time, reloads user settings,
and restarts services only for domains it changed, so a no-drift apply leaves
Dock, Finder, and SystemUIServer alone. A partial write failure reloads the
domains already written,
reports failure, and can be retried. Reload errors fail apply; killall's explicit
"No matching processes" result means the service is not running and is harmless.
`--no-reload` deliberately skips this step. Diff remains read-only.

Dock folder paths own membership/order; existing arrangement, display, and
stack-view fields survive list rewrites. New folders receive default display
fields. File URLs escape literal percent/hash characters.

Use `macos-settings diff` for a read-only comparison. After changing settings
in System Settings or an app, run `task capture`, inspect the diff, and commit
only intentional public-safe changes. Capture updates declared keys only; it
never discovers or adds undeclared preferences. Capture writes a temporary file,
flushes it, and atomically replaces the ledger only if the source bytes still
match its initial snapshot. This detects edits during capture; it is an optimistic
conflict check, not a lock against an editor writing after the final check. A per-app shortcut is a normal
`NSUserKeyEquivalents` dictionary in that app's domain.

Not synced: TCC/GUI consent, current input source, displays and other hardware
state, app sessions/databases, or account-bound preferences. Raycast hotkeys,
extensions, and Script Command registration stay in Raycast Cloud Sync or a
manual `.rayconfig` export. The root script owns software-update policy,
including `AutomaticallyInstallMacOSUpdates = false`; agents never run it.
