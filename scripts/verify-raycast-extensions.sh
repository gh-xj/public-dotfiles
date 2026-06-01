#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
extensions_file="$repo_root/config/raycast/extensions.tsv"
open_missing=0

usage() {
  cat <<'EOF'
Usage: scripts/verify-raycast-extensions.sh [--open-missing]

Check the public desired Raycast Store extension ledger. With --open-missing,
open Raycast install intents for missing extensions. Store extensions are
installed through Raycast, so this verifier is intentionally not part of the
blocking dotfiles gate.
EOF
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --open-missing)
        open_missing=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        printf 'raycast-extensions: unknown option: %s\n' "$1" >&2
        exit 1
        ;;
    esac
    shift
  done
}

installed_extensions() {
  local dir

  for dir in \
    "$HOME/.config/raycast/extensions" \
    "$HOME/Library/Application Support/com.raycast.macos/extensions"
  do
    [ -d "$dir" ] || continue
    find "$dir" -maxdepth 2 -name package.json -print
  done |
    sort -u |
    while IFS= read -r package_json; do
      plutil -extract name raw -o - "$package_json" 2>/dev/null || true
    done |
    sort -u
}

raycast_deeplink() {
  local url="$1"
  local path

  path="${url#https://www.raycast.com/}"
  path="${path%%\?*}"
  printf 'raycast://extensions/%s?source=webstore\n' "$path"
}

main() {
  local installed missing=0 name title url deeplink
  parse_args "$@"

  [ "$(uname -s)" = "Darwin" ] || {
    echo "Raycast extension verification skipped on non-Darwin host"
    exit 0
  }
  [ -f "$extensions_file" ] || {
    printf 'missing Raycast extension ledger: %s\n' "$extensions_file" >&2
    exit 1
  }

  installed="$(installed_extensions)"

  while IFS=$'\t' read -r name title url; do
    case "$name" in
      ""|\#*)
        continue
        ;;
    esac

    if ! grep -Fx -- "$name" <<<"$installed" >/dev/null; then
      missing=$((missing + 1))
      printf 'missing Raycast extension: %s (%s) %s\n' "$title" "$name" "$url" >&2
      if [ "$open_missing" -eq 1 ]; then
        deeplink="$(raycast_deeplink "$url")"
        printf 'opening Raycast install intent: %s\n' "$deeplink" >&2
        open "$deeplink"
      fi
    fi
  done <"$extensions_file"

  if [ "$missing" -gt 0 ]; then
    printf 'missing Raycast extensions: %s\n' "$missing" >&2
    exit 1
  fi

  echo "Raycast extension desired state verified"
}

main "$@"
