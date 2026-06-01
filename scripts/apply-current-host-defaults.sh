#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
defaults_file="$repo_root/config/macos/current-host-defaults.tsv"
mode="verify"

usage() {
  cat <<'EOF'
Usage: scripts/apply-current-host-defaults.sh [--verify|--apply]

Verify or apply public-safe macOS ByHost/currentHost defaults. These settings
cover input behavior that nix-darwin's ordinary defaults do not fully converge,
such as tap-to-click and trackpad gestures.
EOF
}

read_current_host_default() {
  local domain="$1"
  local key="$2"

  defaults -currentHost read "$domain" "$key" 2>/dev/null || printf '<unset>'
}

write_current_host_default() {
  local domain="$1"
  local key="$2"
  local type="$3"
  local value="$4"

  case "$type" in
    bool)
      defaults -currentHost write "$domain" "$key" -bool "$value"
      ;;
    int)
      defaults -currentHost write "$domain" "$key" -int "$value"
      ;;
    float)
      defaults -currentHost write "$domain" "$key" -float "$value"
      ;;
    string)
      defaults -currentHost write "$domain" "$key" -string "$value"
      ;;
    *)
      printf 'current-host-defaults: unsupported type for %s %s: %s\n' "$domain" "$key" "$type" >&2
      exit 1
      ;;
  esac
}

visit_defaults() {
  local callback="$1"
  local domain key type value

  [ -f "$defaults_file" ] || {
    printf 'missing currentHost defaults ledger: %s\n' "$defaults_file" >&2
    exit 1
  }

  while IFS=$'\t' read -r domain key type value; do
    case "$domain" in
      ""|\#*)
        continue
        ;;
    esac
    "$callback" "$domain" "$key" "$type" "$value"
  done <"$defaults_file"
}

verify_one() {
  local domain="$1"
  local key="$2"
  local type="$3"
  local expected="$4"
  local actual

  actual="$(read_current_host_default "$domain" "$key")"
  if [ "$actual" != "$expected" ]; then
    printf 'currentHost default mismatch: %s %s expected %s got %s\n' "$domain" "$key" "$expected" "$actual" >&2
    exit 1
  fi
}

apply_one() {
  local domain="$1"
  local key="$2"
  local type="$3"
  local value="$4"

  write_current_host_default "$domain" "$key" "$type" "$value"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --verify)
      mode="verify"
      ;;
    --apply)
      mode="apply"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'current-host-defaults: unknown option: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

if [ "$(uname -s)" != "Darwin" ]; then
  echo "currentHost defaults skipped on non-Darwin host"
  exit 0
fi

case "$mode" in
  apply)
    visit_defaults apply_one
    killall cfprefsd >/dev/null 2>&1 || true
    echo "currentHost defaults applied"
    ;;
  verify)
    visit_defaults verify_one
    echo "currentHost defaults baseline verified"
    ;;
esac
