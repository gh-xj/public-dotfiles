# macOS Settings

`config/macos/settings.json` is the public, user-level defaults ledger. It
syncs keyboard repeat, pointer and trackpad behavior, input sources, symbolic
hotkeys, Dock/menu bar/Mission Control/Stage Manager layout, desktop icons,
Finder, Raycast plain preferences, and Super Easy Timer.

Home Manager runs `macos-settings apply` during activation. Apply preserves
plist types, merges symbolic hotkeys one ID at a time, reloads user settings,
and restarts Dock, Finder, or SystemUIServer only when an owned domain changed.

Use `macos-settings diff` for a read-only comparison. After changing settings
in System Settings or an app, run `task capture`, inspect the diff, and commit
only intentional public-safe changes. Capture updates declared keys only; it
never discovers or adds undeclared preferences. A per-app shortcut is a normal
`NSUserKeyEquivalents` dictionary in that app's domain.

Not synced: TCC/GUI consent, current input source, displays and other hardware
state, app sessions/databases, or account-bound preferences. Raycast hotkeys,
extensions, and Script Command registration stay in Raycast Cloud Sync or a
manual `.rayconfig` export. The root script owns software-update policy,
including `AutomaticallyInstallMacOSUpdates = false`; agents never run it.
