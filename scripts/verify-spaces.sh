#!/usr/bin/env bash
set -euo pipefail

desired="${XJ_PUBLIC_DOTFILES_SPACES_COUNT:-4}"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Spaces verification skipped on non-Darwin host"
  exit 0
fi

count="$(defaults export com.apple.spaces - 2>/dev/null | plutil -extract "SpacesDisplayConfiguration.Management Data.Monitors.0.Spaces" raw -o - - 2>/dev/null || printf '0')"

if [ "$count" = "$desired" ]; then
  echo "Spaces baseline verified"
  exit 0
fi

printf 'Spaces mismatch: expected %s got %s\n' "$desired" "$count" >&2
printf 'This is not in the blocking gate because creating Spaces requires Mission Control UI automation and Accessibility consent.\n' >&2
exit 1
