#!/usr/bin/env bash

# @raycast.schemaVersion 1
# @raycast.title Insert Current DateTime
# @raycast.mode silent
# @raycast.packageName Public Dotfiles

set -euo pipefail

osascript -e "tell application \"System Events\" to keystroke \"$(date "+%Y-%m-%d %H:%M:%S")\"" &
