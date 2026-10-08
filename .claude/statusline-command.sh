#!/usr/bin/env bash
# Claude Code statusLine — mirrors .config/starship.toml (directory, hostname, git_branch, time)
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

{ IFS= read -r cwd; IFS= read -r model; IFS= read -r remaining; } < <(
    printf '%s' "$input" | jq -r '(.cwd // .workspace.current_dir // ""), (.model.display_name // ""), (.context_window.remaining_percentage // "")')

git_() { git --no-optional-locks -C "$cwd" "$@" 2>/dev/null; }

# [directory]: ~ for home, rooted at the git repo, at most 3 components with a leading …/
top=$(git_ rev-parse --show-toplevel)
if [[ -n "$top" ]]; then
    path="${top##*/}${cwd#"$top"}"
else
    path="$cwd"
    [[ "$path" == "$HOME" || "$path" == "$HOME"/* ]] && path="~${path#"$HOME"}"
fi
IFS=/ read -ra parts <<< "${path#/}"
if (( ${#parts[@]} > 3 )); then
    path="…/${parts[*]: -3:1}/${parts[*]: -2:1}/${parts[*]: -1}"
fi

# [git_branch]: symbol + branch (short SHA when detached). [git_status] is disabled in Starship.
branch=$(git_ symbolic-ref --quiet --short HEAD || git_ rev-parse --short HEAD)

branch_symbol=$'\xef\x90\x98 '  # [git_branch] symbol in .config/starship.toml
bold_cyan=$'\e[1;36m' bold_purple=$'\e[1;35m' bold_yellow=$'\e[1;33m' bold_red=$'\e[1;31m' reset=$'\e[0m'

out=""
# [hostname]: ssh_only
[[ -n "${SSH_CONNECTION:-}" ]] && out+="on ${bold_red}$(hostname -s)${reset} "
out+="${bold_cyan}${path}${reset}"
[[ -n "$branch" ]] && out+=" on ${bold_purple}${branch_symbol}${branch}${reset}"
[[ -n "$model" ]] && out+="  ${model}"
[[ -n "$remaining" ]] && out+=" ctx:${remaining}%"
# [time] is Starship's right_format; a status line cannot right-align.
out+="  ${bold_yellow}$(date +%H:%M:%S)${reset}"

printf '%s' "$out"
