#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
defaults_file="$repo_root/config/macos/current-host-defaults.tsv"
user_defaults_file="$repo_root/config/macos/input-user-defaults.tsv"
live_trackpad_defaults_file="$repo_root/config/macos/live-trackpad-defaults.tsv"
mode="verify"

usage() {
  cat <<'EOF'
Usage: scripts/apply-current-host-defaults.sh [--verify|--apply|--reload-live]

Verify or apply public-safe macOS input defaults. These settings cover input
behavior that nix-darwin's ordinary defaults do not fully converge, such as
tap-to-click and trackpad gestures. Verification checks both persisted defaults
and the live AppleMultitouchDevice state.

--reload-live prompts for sudo when needed and asks the GUI user session to
reload input preferences without rewriting defaults.
EOF
}

expected_defaults_read_value() {
  local type="$1"
  local value="$2"

  case "$type:$value" in
    bool:true)
      printf '1'
      ;;
    bool:false)
      printf '0'
      ;;
    *)
      printf '%s' "$value"
      ;;
  esac
}

read_default() {
  local scope="$1"
  local domain="$2"
  local key="$3"

  case "$scope" in
    currentHost)
      defaults -currentHost read "$domain" "$key" 2>/dev/null || printf '<unset>'
      ;;
    user)
      defaults read "$domain" "$key" 2>/dev/null || printf '<unset>'
      ;;
    *)
      printf 'input-defaults: unsupported scope: %s\n' "$scope" >&2
      exit 1
      ;;
  esac
}

write_default() {
  local scope="$1"
  local domain="$2"
  local key="$3"
  local type="$4"
  local value="$5"
  local defaults_args=()

  case "$scope" in
    currentHost)
      defaults_args=(-currentHost)
      ;;
    user)
      defaults_args=()
      ;;
    *)
      printf 'input-defaults: unsupported scope: %s\n' "$scope" >&2
      exit 1
      ;;
  esac

  case "$type" in
    bool)
      defaults "${defaults_args[@]}" write "$domain" "$key" -bool "$value"
      ;;
    int)
      defaults "${defaults_args[@]}" write "$domain" "$key" -int "$value"
      ;;
    float)
      defaults "${defaults_args[@]}" write "$domain" "$key" -float "$value"
      ;;
    string)
      defaults "${defaults_args[@]}" write "$domain" "$key" -string "$value"
      ;;
    *)
      printf 'input-defaults: unsupported type for %s %s: %s\n' "$domain" "$key" "$type" >&2
      exit 1
      ;;
  esac
}

visit_defaults() {
  local scope="$1"
  local file="$2"
  local callback="$3"
  local domain key type value

  [ -f "$file" ] || {
    printf 'missing input defaults ledger: %s\n' "$file" >&2
    exit 1
  }

  while IFS=$'\t' read -r domain key type value; do
    case "$domain" in
      ""|\#*)
        continue
        ;;
    esac
    "$callback" "$scope" "$domain" "$key" "$type" "$value"
  done <"$file"
}

verify_one() {
  local scope="$1"
  local domain="$2"
  local key="$3"
  local type="$4"
  local value="$5"
  local expected
  local actual

  expected="$(expected_defaults_read_value "$type" "$value")"
  actual="$(read_default "$scope" "$domain" "$key")"
  if [ "$actual" != "$expected" ]; then
    printf '%s default mismatch: %s %s expected %s got %s\n' "$scope" "$domain" "$key" "$expected" "$actual" >&2
    exit 1
  fi
}

apply_one() {
  local scope="$1"
  local domain="$2"
  local key="$3"
  local type="$4"
  local value="$5"

  write_default "$scope" "$domain" "$key" "$type" "$value"
}

live_trackpad_preferences() {
  ioreg -r -c AppleMultitouchDevice -l -w0 2>/dev/null |
    sed -n 's/.*"MultitouchPreferences" = {\(.*\)}.*/\1/p' |
    head -1
}

read_live_trackpad_default() {
  local key="$1"
  local prefs="$2"

  printf '%s\n' "$prefs" |
    sed -nE "s/.*\"$key\"=([^,}]+).*/\1/p"
}

verify_live_trackpad_defaults() {
  local prefs key expected actual failed=0

  [ -f "$live_trackpad_defaults_file" ] || {
    printf 'missing live trackpad defaults ledger: %s\n' "$live_trackpad_defaults_file" >&2
    exit 1
  }

  prefs="$(live_trackpad_preferences)"
  if [ -z "$prefs" ]; then
    echo "live trackpad baseline skipped; no AppleMultitouchDevice preferences found"
    return 0
  fi

  while IFS=$'\t' read -r key expected; do
    case "$key" in
      ""|\#*)
        continue
        ;;
    esac
    actual="$(read_live_trackpad_default "$key" "$prefs")"
    if [ "$actual" != "$expected" ]; then
      printf 'live trackpad mismatch: %s expected %s got %s\n' "$key" "$expected" "${actual:-<unset>}" >&2
      failed=1
    fi
  done <"$live_trackpad_defaults_file"

  if [ "$failed" -ne 0 ]; then
    printf '%s\n' "Persisted defaults may be correct, but the live AppleMultitouchDevice state has not reloaded." >&2
    printf '%s\n' "Run: task input:reload-live" >&2
    printf '%s\n' "If that still does not converge, log out/in after applying input defaults." >&2
    return 1
  fi

  echo "live trackpad baseline verified"
}

activate_input_defaults() {
  local sudo_mode="${1:-noninteractive}"
  local activate_settings="/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
  local uid

  [ -x "$activate_settings" ] || return 0

  "$activate_settings" -u -forcePrefUpdate >/dev/null 2>&1 || true
  if verify_live_trackpad_defaults >/dev/null 2>&1; then
    return 0
  fi

  uid="$(id -u)"
  if sudo -n true >/dev/null 2>&1; then
    sudo launchctl asuser "$uid" "$activate_settings" -u -forcePrefUpdate >/dev/null 2>&1 || true
  elif [ "$sudo_mode" = "interactive" ]; then
    sudo launchctl asuser "$uid" "$activate_settings" -u -forcePrefUpdate >/dev/null 2>&1 || true
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --verify)
      mode="verify"
      ;;
    --apply)
      mode="apply"
      ;;
    --reload-live)
      mode="reload-live"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'input-defaults: unknown option: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

if [ "$(uname -s)" != "Darwin" ]; then
  echo "input defaults skipped on non-Darwin host"
  exit 0
fi

case "$mode" in
  apply)
    visit_defaults currentHost "$defaults_file" apply_one
    visit_defaults user "$user_defaults_file" apply_one
    killall cfprefsd >/dev/null 2>&1 || true
    activate_input_defaults
    verify_live_trackpad_defaults
    echo "input defaults applied"
    ;;
  reload-live)
    killall cfprefsd >/dev/null 2>&1 || true
    activate_input_defaults interactive
    verify_live_trackpad_defaults
    echo "live input defaults reloaded"
    ;;
  verify)
    visit_defaults currentHost "$defaults_file" verify_one
    visit_defaults user "$user_defaults_file" verify_one
    verify_live_trackpad_defaults
    echo "input defaults baseline verified"
    ;;
esac
