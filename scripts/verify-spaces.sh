#!/usr/bin/env bash
set -euo pipefail

desired="${XJ_PUBLIC_DOTFILES_SPACES_COUNT:-4}"
mode="verify"

usage() {
  cat <<'EOF'
Usage: scripts/verify-spaces.sh [--verify|--apply|--request-permission]

Verify or attempt to create the desired Mission Control Spaces count. Creation
requires Accessibility consent for the controlling app/process.
EOF
}

current_spaces_count() {
  defaults export com.apple.spaces - 2>/dev/null |
    plutil -extract "SpacesDisplayConfiguration.Management Data.Monitors.0.Spaces" raw -o - - 2>/dev/null ||
    printf '0'
}

accessibility_enabled() {
  [ "$(osascript -e 'tell application "System Events" to return UI elements enabled' 2>/dev/null || printf false)" = "true" ]
}

open_accessibility_settings() {
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
}

apply_spaces() {
  local count missing

  count="$(current_spaces_count)"
  if [ "$count" -ge "$desired" ]; then
    echo "Spaces baseline already satisfied"
    return 0
  fi

  if ! accessibility_enabled; then
    open_accessibility_settings
    printf 'Spaces apply requires Accessibility consent. Grant it to the controlling terminal/SSH process, then rerun: task spaces:apply\n' >&2
    return 2
  fi

  missing=$((desired - count))
  osascript <<EOF
set missingSpaces to $missing
tell application "Finder" to set desktopBounds to bounds of window of desktop
set clickX to (item 3 of desktopBounds) - 40
tell application "System Events"
  repeat missingSpaces times
    key code 126 using control down
    delay 0.8
    click at {clickX, 40}
    delay 0.4
    key code 53
    delay 0.4
  end repeat
end tell
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --verify)
      mode="verify"
      ;;
    --apply)
      mode="apply"
      ;;
    --request-permission)
      mode="request-permission"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Spaces: unknown option: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Spaces verification skipped on non-Darwin host"
  exit 0
fi

case "$mode" in
  request-permission)
    if accessibility_enabled; then
      echo "Accessibility is already enabled for this automation context"
    else
      open_accessibility_settings
      echo "Opened Accessibility settings"
    fi
    exit 0
    ;;
  apply)
    apply_spaces
    ;;
esac

count="$(current_spaces_count)"
if [ "$count" = "$desired" ]; then
  echo "Spaces baseline verified"
  exit 0
fi

printf 'Spaces mismatch: expected %s got %s\n' "$desired" "$count" >&2
printf 'This is not in the blocking gate because creating Spaces requires Mission Control UI automation and Accessibility consent.\n' >&2
exit 1
