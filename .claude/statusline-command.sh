#!/usr/bin/env bash
# Claude Code statusLine — mirrors Starship prompt style
# Receives JSON on stdin from Claude Code

input=$(cat)

label=$(printf '%s' "$input" | jq -r '
  (.session_name // "") as $s | (.agent.name // "") as $a |
  if $s != "" and $a != "" then "Claude/" + $a + " · " + $s
  elif $s != "" then "Claude · " + $s
  elif $a != "" then "Claude/" + $a else "" end')
if command -v agent-pane-title >/dev/null 2>&1; then
    if [[ -n "$label" ]]; then
        agent-pane-title set "$label" 2>/dev/null || true
    fi
fi
# No name yet: preserve SessionStart's pane-only fallback. Native pane_title
# may change via OSC and is never read back as Claude's identity.

cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

# Directory: basename of cwd
dir=$(basename "$cwd")

# Git branch (Starship has git_status disabled, so no file counts)
branch=$(git --no-optional-locks -C "$cwd" symbolic-ref --quiet --short HEAD 2>/dev/null \
         || git --no-optional-locks -C "$cwd" rev-parse --short HEAD 2>/dev/null)

# Starship default styles: directory bold cyan, git_branch bold purple,
# time bold yellow, character bold green; hostname only over SSH.
bold_green=$'\e[1;32m' bold_cyan=$'\e[1;36m' bold_purple=$'\e[1;35m'
bold_yellow=$'\e[1;33m' bold_blue=$'\e[1;34m' bold_red=$'\e[1;31m'
dim=$'\e[2m' reset=$'\e[0m'

parts="${bold_green}➜${reset} "
if [[ -n "${SSH_CONNECTION:-}" ]]; then
    parts+="${bold_blue}${reset} on ${bold_red}$(hostname -s)${reset} "
fi
parts+="${bold_cyan}${dir}${reset}"
if [[ -n "$branch" ]]; then
    parts+=" on ${bold_purple} ${branch}${reset}"
fi

# Claude-only context, dimmed so the Starship-shaped part stays primary
extra=""
[[ -n "$model" ]] && extra+="  ${model}"
[[ -n "$remaining" ]] && extra+=" ctx:${remaining}%"
[[ -n "$extra" ]] && parts+="${dim}${extra}${reset}"

parts+="  ${bold_yellow}$(date +%H:%M:%S)${reset}"

printf '%s' "$parts"
