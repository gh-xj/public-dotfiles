#!/usr/bin/env bash

# @raycast.schemaVersion 1
# @raycast.title Switch Input to Shuangpin
# @raycast.mode silent
# @raycast.packageName Public Dotfiles

set -euo pipefail

osascript -e 'tell application "System Events" to keystroke "space" using {control down, option down}'
