#!/usr/bin/env bash

# @raycast.schemaVersion 1
# @raycast.title switch input source to cn
# @raycast.mode silent
# @raycast.currentDirectoryPath ~
# @raycast.packageName Raycast Scripts

set -euo pipefail

osascript -e 'tell application "System Events" to keystroke "space" using {control down, option down}'
