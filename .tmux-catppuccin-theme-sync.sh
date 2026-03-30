#!/usr/bin/env bash
set -euo pipefail

appearance=$(osascript -e 'tell application "System Events" to tell appearance preferences to get dark mode')
appearance=$(echo "$appearance" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

if [ "$appearance" = "true" ]; then
  tmux set -g @catppuccin_flavor "mocha"
else
  tmux set -g @catppuccin_flavor "latte"
fi

tmux run-shell "$HOME/.config/tmux/plugins/catppuccin/tmux/catppuccin.tmux"
