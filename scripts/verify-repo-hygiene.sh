#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

tracked_noise="$(
  git ls-files |
    rg '(^|/)\.DS_Store$|^\.config/karabiner/automatic_backups/|^\.config/nvim/_machine_specific(_default)?\.vim$' || true
)"

if [ -n "$tracked_noise" ]; then
  printf '%s\n' "tracked repo noise detected:" >&2
  printf '%s\n' "$tracked_noise" >&2
  printf '%s\n' "Remove these files from git and rely on .gitignore instead." >&2
  exit 1
fi

echo "repo hygiene verified"
