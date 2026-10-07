#!/usr/bin/env bash

# @raycast.schemaVersion 1
# @raycast.title command open chrome
# @raycast.mode silent
# @raycast.currentDirectoryPath ~
# @raycast.packageName Raycast Scripts

set -euo pipefail

app_name="Google Chrome"
open -a "$app_name"

osascript -e "tell application \"System Events\" to tell process \"$app_name\"
  if not (exists window 1) then keystroke \"n\" using command down
end tell"
