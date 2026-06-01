#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ledger="$repo_root/config/raycast/script-commands.tsv"
repo_scripts_dir="$repo_root/.config/raycast/scripts"
live_scripts_dir="$HOME/.config/raycast/scripts"
compat_scripts_dir="$HOME/.config/xj_public_raycast_scripts"
open_setup=0
strict=0

usage() {
  cat <<'USAGE'
Usage: diagnose-raycast-runtime.sh [--open-setup] [--strict]

Checks the repo-owned Raycast Script Command files and reports the remaining
Raycast runtime setup that cannot be represented as public dotfiles.

--open-setup  Copy the stable script directory path and open Raycast Settings.
--strict      Exit non-zero when Raycast runtime state cannot be verified.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --open-setup)
      open_setup=1
      ;;
    --strict)
      strict=1
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Raycast runtime diagnosis skipped on non-Darwin host"
  exit 0
fi

section() {
  printf '\n## %s\n' "$1"
}

warn() {
  printf 'WARN: %s\n' "$1" >&2
}

resolve_final() {
  local path="$1"
  local target dir

  while [ -L "$path" ]; do
    target="$(readlink "$path")"
    case "$target" in
      /*)
        path="$target"
        ;;
      *)
        dir="$(cd -- "$(dirname -- "$path")" && pwd)"
        path="$dir/$target"
        ;;
    esac
  done

  printf '%s\n' "$path"
}

runtime_unknown=0

section "Repo-Owned Script Commands"
"$repo_root/scripts/verify-raycast-script-commands.sh"

if [ -d "$live_scripts_dir" ] || [ -L "$live_scripts_dir" ]; then
  "$repo_root/scripts/verify-raycast-script-commands.sh" --live
else
  warn "Home Manager live Raycast script path is missing: $live_scripts_dir"
  runtime_unknown=1
fi

section "Stable Directory For Raycast UI"
printf 'add this Script Directory in Raycast: %s\n' "$repo_scripts_dir"
if [ -e "$live_scripts_dir" ] || [ -L "$live_scripts_dir" ]; then
  printf 'Home Manager live path: %s -> %s\n' "$live_scripts_dir" "$(resolve_final "$live_scripts_dir")"
fi
if [ -e "$compat_scripts_dir" ] || [ -L "$compat_scripts_dir" ]; then
  printf 'compat path: %s -> %s\n' "$compat_scripts_dir" "$(resolve_final "$compat_scripts_dir")"
fi

section "Raycast App State"
if [ -d /Applications/Raycast.app ] || [ -d "$HOME/Applications/Raycast.app" ]; then
  echo "Raycast app installed"
else
  warn "Raycast app is not installed"
  runtime_unknown=1
fi

if defaults export com.raycast.macos - >/dev/null 2>&1; then
  echo "Raycast preferences domain exists"
else
  warn "Raycast preferences domain is not initialized"
  runtime_unknown=1
fi

prefs_text="$(defaults export com.raycast.macos - 2>/dev/null | plutil -p - 2>/dev/null || true)"
plaintext_hits=0
for path in "$repo_scripts_dir" "$live_scripts_dir" "$compat_scripts_dir"; do
  if printf '%s\n' "$prefs_text" | grep -F -- "$path" >/dev/null; then
    printf 'plaintext preferences mention script directory: %s\n' "$path"
    plaintext_hits=$((plaintext_hits + 1))
  fi
done

if [ -f "$ledger" ]; then
  while IFS=$'\t' read -r script title mode package boundary notes; do
    case "$script" in
      ""|\#*)
        continue
        ;;
    esac
    if printf '%s\n' "$prefs_text" | grep -F -- "$title" >/dev/null; then
      printf 'plaintext preferences mention command title: %s\n' "$title"
      plaintext_hits=$((plaintext_hits + 1))
    fi
  done <"$ledger"
fi

if [ "$plaintext_hits" -eq 0 ]; then
  warn "Script Directory registration, command aliases, and command hotkeys are not visible in public-safe plaintext defaults."
  warn "Raycast stores this runtime state in app-managed data; use Raycast UI or encrypted .rayconfig import for those pieces."
  runtime_unknown=1
fi

section "Manual Runtime Step"
cat <<EOF
1. Open Raycast Settings.
2. Go to Extensions -> Script Commands.
3. Add Script Directory: $repo_scripts_dir
4. In Raycast root search, find each script command and use Configure Command to set aliases/hotkeys.

Public dotfiles verify the script files and metadata. Raycast aliases/hotkeys
are intentionally not committed because Raycast exports them through encrypted
.rayconfig bundles that can include broader app/account/runtime state.
EOF

if [ "$open_setup" -eq 1 ]; then
  printf '%s' "$repo_scripts_dir" | pbcopy
  open -a Raycast
  osascript >/dev/null 2>&1 <<'APPLESCRIPT' || true
tell application "Raycast" to activate
delay 0.5
tell application "System Events" to keystroke "," using {command down}
APPLESCRIPT
  printf '\nCopied Script Directory to clipboard and opened Raycast Settings.\n'
fi

if [ "$strict" -eq 1 ] && [ "$runtime_unknown" -ne 0 ]; then
  exit 1
fi

exit 0
