#!/usr/bin/env bash
set -euo pipefail

appearance=$(osascript -e 'tell application "System Events" to tell appearance preferences to get dark mode' 2>/dev/null || true)
appearance=$(echo "$appearance" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

theme="light"
if [[ "$appearance" == "true" ]]; then
  theme="dark"
fi

command claude --settings "{\"theme\":\"${theme}\"}" "$@"
