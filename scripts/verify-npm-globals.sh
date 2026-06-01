#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ledger="$repo_root/npm-globals.txt"

[ -f "$ledger" ] || exit 0

xdg_data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
npm_prefix="${NPM_CONFIG_PREFIX:-$xdg_data_home/npm-global}"
export PATH="$npm_prefix/bin:$PATH"

while IFS= read -r spec || [ -n "$spec" ]; do
  spec="${spec%%#*}"
  spec="${spec#"${spec%%[![:space:]]*}"}"
  spec="${spec%"${spec##*[![:space:]]}"}"
  [ -n "$spec" ] || continue

  package="${spec%@*}"
  if [ -z "$package" ]; then
    package="$spec"
  fi

  case "$package" in
    ccusage)
      command -v ccusage >/dev/null 2>&1 || {
        printf 'missing npm global command: ccusage\n' >&2
        exit 1
      }
      ;;
    *)
      printf 'no verifier mapping for npm global package: %s\n' "$package" >&2
      exit 1
      ;;
  esac
done < "$ledger"

echo "npm global baseline verified"
