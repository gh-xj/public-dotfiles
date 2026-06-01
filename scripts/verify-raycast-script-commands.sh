#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ledger="$repo_root/config/raycast/script-commands.tsv"
scripts_dir="$repo_root/.config/raycast/scripts"

usage() {
  cat <<'USAGE'
Usage: verify-raycast-script-commands.sh [--live]

Verifies the public Raycast Script Commands ledger against repo source.
With --live, verifies the Home Manager-linked live script directory instead.
USAGE
}

if [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "${1:-}" = "--live" ]; then
  scripts_dir="$HOME/.config/raycast/scripts"
elif [ "${1:-}" != "" ]; then
  usage >&2
  exit 2
fi

if [ ! -f "$ledger" ]; then
  printf 'missing Raycast script command ledger: %s\n' "$ledger" >&2
  exit 1
fi

if [ ! -d "$scripts_dir" ]; then
  printf 'missing Raycast script command directory: %s\n' "$scripts_dir" >&2
  exit 1
fi

tmp_expected="$(mktemp)"
tmp_actual="$(mktemp)"
trap 'rm -f "$tmp_expected" "$tmp_actual"' EXIT

header_value() {
  local file="$1"
  local key="$2"

  sed -n "s/^# @raycast\\.$key //p" "$file" | head -n 1
}

assert_header() {
  local file="$1"
  local key="$2"
  local expected="$3"
  local actual

  actual="$(header_value "$file" "$key")"
  if [ "$actual" != "$expected" ]; then
    printf '%s: expected @raycast.%s=%s, got %s\n' \
      "${file#$repo_root/}" "$key" "$expected" "${actual:-<unset>}" >&2
    return 1
  fi
}

fail=0
while IFS=$'\t' read -r script title mode package boundary notes; do
  case "$script" in
    ""|\#*)
      continue
      ;;
  esac

  printf '%s\n' "$script" >>"$tmp_expected"
  script_file="$scripts_dir/$script"

  if [ ! -f "$script_file" ]; then
    printf 'missing Raycast script command: %s\n' "$script_file" >&2
    fail=1
    continue
  fi

  if [ ! -x "$script_file" ]; then
    printf 'Raycast script command is not executable: %s\n' "$script_file" >&2
    fail=1
  fi

  assert_header "$script_file" schemaVersion 1 || fail=1
  assert_header "$script_file" title "$title" || fail=1
  assert_header "$script_file" mode "$mode" || fail=1
  assert_header "$script_file" packageName "$package" || fail=1

  if [ "$boundary" != "public" ]; then
    printf '%s: unexpected boundary %s\n' "${script_file#$repo_root/}" "$boundary" >&2
    fail=1
  fi

  if grep -nE '(private-config|xj-private|bytedance|ByteDance|token|secret|password|api[_-]?key|oauth|bearer|Authorization|/Users/xj|/Users/bytedance)' "$script_file" >/dev/null; then
    printf '%s: contains private/sensitive-looking strings\n' "${script_file#$repo_root/}" >&2
    fail=1
  fi

  case "$script_file" in
    *.sh)
      bash -n "$script_file" || fail=1
      ;;
  esac
done <"$ledger"

find -L "$scripts_dir" -maxdepth 1 -type f \( -name '*.sh' -o -name '*.py' -o -name '*.js' \) -exec basename {} \; |
  sort >"$tmp_actual"
sort -o "$tmp_expected" "$tmp_expected"

if ! diff -u "$tmp_expected" "$tmp_actual" >/dev/null; then
  printf 'Raycast script directory does not match ledger:\n' >&2
  diff -u "$tmp_expected" "$tmp_actual" >&2 || true
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi

printf 'Raycast script command baseline verified\n'
