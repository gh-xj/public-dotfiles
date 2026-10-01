#!/usr/bin/env bash
# Push an agent attention event to ntfy, only while the Mac is idle (xj away).
# The ntfy topic URL is a bearer secret kept outside Git in the file below.
set -euo pipefail
agent="${1:-agent}"
event="${2:-attention}"
url_file="${XDG_CONFIG_HOME:-$HOME/.config}/agent-notify/ntfy-url"
[[ -r "$url_file" ]] || exit 0
url="$(<"$url_file")"
[[ "$url" == https://* ]] || exit 0

idle_ns="$(/usr/sbin/ioreg -c IOHIDSystem | awk '/HIDIdleTime/ { print $NF; exit }')"
(( ${idle_ns:-0} / 1000000000 >= ${AGENT_NOTIFY_IDLE_SECS:-120} )) || exit 0

payload="$(cat || true)"
cwd="$(jq -r '.cwd // empty' <<<"$payload" 2>/dev/null || true)"
kind="$(jq -r '.notification_type // empty' <<<"$payload" 2>/dev/null || true)"
case "${kind:-$event}" in
    permission_prompt | permission) text="needs permission" ;;
    idle_prompt | done) text="is waiting for input" ;;
    *) text="needs attention" ;;
esac
where="${cwd##*/}"
if [[ -n "${TMUX_PANE:-}" ]]; then
    where="$(tmux display-message -p -t "$TMUX_PANE" '#S:#W' 2>/dev/null || printf '%s' "$where")"
fi

# Never block the agent on the network.
curl -fsS -m 5 -o /dev/null \
    -H "Title: $agent · ${where:-?}" \
    -H "Tags: robot" \
    -d "$agent $text" \
    "$url" >/dev/null 2>&1 &
disown
