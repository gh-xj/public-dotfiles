#!/bin/bash
# Thin shim: AppleScript wrapper invokes this, which delegates to the Go binary.
# The Go binary handles all logic and writes its own log to /tmp/nvim-tmux.log.
exec "$(dirname "$0")/nvim-tmux" "$@"
