#!/usr/bin/env bash
# Claude Code statusLine — mirrors Starship prompt style
# Receives JSON on stdin from Claude Code

input=$(cat)

cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

# Directory: basename of cwd
dir=$(basename "$cwd")

# Git branch (skip lock to avoid conflicts with running agents)
branch=$(git -C "$cwd" symbolic-ref --quiet --short HEAD 2>/dev/null \
         || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)

# Git status indicators (staged / modified / untracked)
git_status=""
if [[ -n "$branch" ]]; then
    st=$(git -C "$cwd" status --porcelain 2>/dev/null)
    staged=$(echo "$st" | grep -c '^[MADRC]' 2>/dev/null || echo 0)
    modified=$(echo "$st" | grep -c '^ [MD]' 2>/dev/null || echo 0)
    untracked=$(echo "$st" | grep -c '^??' 2>/dev/null || echo 0)

    [[ "$staged"    -gt 0 ]] && git_status+=" +${staged}"
    [[ "$modified"  -gt 0 ]] && git_status+=" ~${modified}"
    [[ "$untracked" -gt 0 ]] && git_status+=" ?${untracked}"
fi

# Context window
ctx_str=""
if [[ -n "$remaining" ]]; then
    ctx_str=" ctx:${remaining}%"
fi

# Time
time_str=$(date +%H:%M:%S)

# Assemble line
parts=""

# user@dir
parts="$(whoami)@${dir}"

# git
if [[ -n "$branch" ]]; then
    parts+="  ${branch}${git_status}"
fi

# model
if [[ -n "$model" ]]; then
    parts+="  ${model}"
fi

# context
parts+="${ctx_str}"

# time (right-aligned feel — just append)
parts+="  ${time_str}"

printf '%s' "$parts"
