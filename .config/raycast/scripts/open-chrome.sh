#!/usr/bin/env bash

# @raycast.schemaVersion 1
# @raycast.title Open Chrome
# @raycast.mode silent
# @raycast.packageName Public Dotfiles

set -euo pipefail

app_name="Google Chrome"
open -a "$app_name"

osascript -e "tell application \"System Events\" to tell process \"$app_name\"
  if not (exists window 1) then keystroke \"n\" using command down
end tell"
