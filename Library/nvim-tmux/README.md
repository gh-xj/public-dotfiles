# nvim-tmux

macOS URL handler that opens files in nvim inside a specific tmux
session/window. Click a link like
`nvim-tmux:///Users/xj/notes/foo.md?session=main&window=zsh` (e.g. from
Godspeed, a browser, or any app with a clickable URL) and the handler:

1. Ensures `session=main` exists in tmux (creates if not).
2. Ensures a window named `zsh` exists in that session (creates if not).
3. Ensures some pane in that window is running `nvim /Users/xj/notes/foo.md`
   (reuses an existing pane, or splits the window to spawn one).
4. Yanks the most-recently-active tmux client (≈ last-focused Ghostty
   window) to that pane, so `open -a Ghostty` raises the right window.

## Layout

```
.
├── main.go          # handler source (stdlib only, ~180 LOC)
├── go.mod
├── handler.sh       # thin shim the .app invokes; delegates to the Go binary
├── bin/nvim-tmux    # prebuilt darwin/arm64 binary, committed
└── README.md
```

## Build and install

```sh
task nvim-tmux:build      # compile bin/nvim-tmux
task nvim-tmux:install    # copy into ~/Applications/nvim-tmux.app
```

`nvim-tmux:install` no-ops if `~/Applications/nvim-tmux.app` doesn't
exist yet — see _First-time setup_ below.

## First-time setup (building the .app bundle)

The handler lives in a macOS `.app` bundle registered with Launch
Services. Creating the bundle from scratch:

```sh
# 1. Scratch AppleScript source
cat > /tmp/handler.applescript <<'APPLESCRIPT'
on open location theURL
	set appPath to POSIX path of (path to me)
	set scriptPath to appPath & "Contents/Resources/handler.sh"
	do shell script "/bin/bash " & quoted form of scriptPath & " " & quoted form of theURL & " >/tmp/nvim-tmux.log 2>&1"
end open location
APPLESCRIPT

# 2. Compile to .app
osacompile -o ~/Applications/nvim-tmux.app /tmp/handler.applescript

# 3. Register the URL scheme and mark the app background-only
PLIST=~/Applications/nvim-tmux.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.xj.nvim-tmux-url-handler" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0 dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLName string nvim-tmux" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string nvim-tmux" "$PLIST"

# 4. Register with Launch Services
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f ~/Applications/nvim-tmux.app

# 5. Drop the binary and shim in
task nvim-tmux:install
```

## URL grammar

```
nvim-tmux://<path>[?session=<name>&window=<name>]
```

- `<path>` is absolute (or `/~/relative/to/home`).
- `session` and `window` are both **required**. Missing either produces a
  macOS notification.
- Window is matched by name. If a window with that name doesn't exist in
  the session, the handler creates one.

## Debugging

Every fire overwrites `/tmp/nvim-tmux.log` with a fresh slog trace:

```sh
tail -n 20 /tmp/nvim-tmux.log
```

Manual invocation (bypassing the URL scheme) for testing:

```sh
~/Applications/nvim-tmux.app/Contents/Resources/nvim-tmux \
  'nvim-tmux:///tmp/foo.md?session=main&window=zsh'
```

## Why Go, not bash

The earlier bash iteration hit six classes of bugs that Go eliminates:

- `set -e` silently aborting `find_pane_in_window` on ps no-matches.
- Mismatched realpath between the raw URL path and nvim's resolved
  argv (`/tmp/x.md` vs `/private/tmp/x.md`).
- URL-decoding via a python3 subprocess per argv token.
- Case-sensitive `pgrep -x Ghostty` missing the lowercase process name
  and triggering the `open -n` chaos.
- Shell-quoting pitfalls around `tmux ... "nvim $path"`.
- Fragile arg-tokenization via `for arg in $argv`.

## Policy: never spawn a new Ghostty window

Programmatically creating a new Ghostty window (`open -na`, AppleScript
`make new window`, cmd+n via System Events, `--command` / `-e`) causes
Ghostty to restore prior tab state with the launch command applied in
ways that leave multiple ghost tmux clients attached to `main`. Two
verified incidents in one session.

The handler therefore **never spawns a new Ghostty window**. When no
tmux client is attached to the target session, it still creates the
tmux state (session/window/pane) but leaves raising Ghostty up to
`open -a Ghostty` without any `-n` or `--args`.
