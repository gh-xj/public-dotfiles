#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ledger="$repo_root/npm-globals.txt"

[ -f "$ledger" ] || exit 0

find_npm() {
  if [ -x "$HOME/.nix-profile/bin/npm" ]; then
    printf '%s\n' "$HOME/.nix-profile/bin/npm"
    return 0
  fi

  if command -v npm >/dev/null 2>&1; then
    command -v npm
    return 0
  fi

  return 1
}

npm_bin="$(find_npm)" || {
  printf 'npm is required to install public npm globals; run Home Manager first\n' >&2
  exit 1
}

xdg_data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
npm_prefix="${NPM_CONFIG_PREFIX:-$xdg_data_home/npm-global}"

mkdir -p "$npm_prefix"

while IFS= read -r spec || [ -n "$spec" ]; do
  spec="${spec%%#*}"
  spec="${spec#"${spec%%[![:space:]]*}"}"
  spec="${spec%"${spec##*[![:space:]]}"}"
  [ -n "$spec" ] || continue

  printf '==> npm global: %s\n' "$spec" >&2
  NPM_CONFIG_PREFIX="$npm_prefix" "$npm_bin" install -g "$spec"
done < "$ledger"
