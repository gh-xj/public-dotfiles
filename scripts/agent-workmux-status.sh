#!/usr/bin/env bash
# Event-driven Workmux transitions. Ordinary tool results execute no subprocess.
set -euo pipefail
event="${1:-}"
case "$event" in working|waiting|done|resume) ;; *) exit 2 ;; esac
[[ -n "${TMUX:-}" && "${TMUX_PANE:-}" == %* ]] || exit 0
pane="${TMUX_PANE#%}"
server="${TMUX%,*}"
server="${server##*,}"
[[ -n "$pane" && -z "${pane//[0-9]/}" && -n "$server" && -z "${server//[0-9]/}" ]] || exit 0
state_dir="${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}}/agent-workmux-status"
marker="$state_dir/$server-$pane.waiting"
if [[ "$event" == resume ]]; then
    [[ -f "$marker" ]] || exit 0
    event=working
fi
if [[ "$event" == waiting ]]; then
    umask 077
    mkdir -p "$state_dir"
    # Mark before the command so an interrupted update can still recover.
    : > "$marker"
fi
workmux set-window-status "$event"
if [[ "$event" != waiting && -f "$marker" ]]; then
    rm -f -- "$marker"
fi
