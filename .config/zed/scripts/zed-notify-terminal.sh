#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 1 ]]; then
  echo "Usage: zed-notify-terminal <command> [args...]" >&2
  exit 64
fi

log_path="${ZED_NOTIFY_LOG:-$HOME/.cache/zed-notify-terminal.log}"
if [[ "${ZED_NOTIFY_DEBUG:-0}" == "1" ]]; then
  mkdir -p "$HOME/.cache"
  {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] command: $*"
    echo "  shell=$SHELL cwd=$PWD pid=$$"
  } >> "$log_path"
fi

notify_delivery=0

notify_command() {
  local title=$1
  local body=$2

  if command -v terminal-notifier >/dev/null 2>&1; then
    terminal-notifier -title "$title" -message "$body" -sound default
    return $?
  fi

  /usr/bin/osascript -e "display notification \"$body\" with title \"$title\""
}

set +e
"$@"
status=$?
set -e

if [[ "${ZED_NOTIFY_DEBUG:-0}" == "1" ]]; then
  {
    echo "  exit=$status"
    echo "  notify_target=$0"
  } >> "$log_path"
fi

if [[ "${NOTIFY_ON_SUCCESS:-1}" == "0" && "$status" -eq 0 ]]; then
  exit 0
fi

if [[ "${NOTIFY_ON_ERROR_ONLY:-0}" == "1" && "$status" -eq 0 ]]; then
  exit 0
fi

command_name="${1##*/}"

if [[ "$status" -eq 0 ]]; then
  title="Zed terminal"
  body="${command_name} completed."
else
  title="Zed terminal"
  body="${command_name} failed (exit $status)."
fi

if [[ "$OSTYPE" == darwin* ]]; then
  # macOS notification center
  notify_command "$title" "$body"
  notify_delivery=$?
  if [[ "${ZED_NOTIFY_DEBUG:-0}" == "1" ]]; then
    echo "  notify_delivery_rc=$notify_delivery" >> "$log_path"
  fi
else
  # Linux notification daemon fallback
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$title" "$body"
    notify_delivery=$?
  else
    printf '\a'
  fi
fi

if [[ "${ZED_NOTIFY_DEBUG:-0}" == "1" && "$notify_delivery" -ne 0 && "$OSTYPE" == linux* ]]; then
  echo "  notify_send_rc=$notify_delivery" >> "$log_path"
fi

exit "$status"
