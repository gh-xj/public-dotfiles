#!/usr/bin/env bash
set -euo pipefail

[ "$#" -eq 0 ] || { printf 'usage: %s\n' "$0" >&2; exit 2; }
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

nix_cmd() {
  nix --extra-experimental-features "nix-command flakes" "$@"
}

gitleaks protect --staged --source . --redact --no-banner
./scripts/verify-denylist.sh
python3 scripts/check-harness-budget.py
nix_cmd flake check --no-write-lock-file
generation="$(nix_cmd build --no-link --print-out-paths .#)"
check_python="$(nix_cmd eval --raw --impure --expr '(builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.${builtins.currentSystem}.python3.outPath')/bin/python3"
python3 scripts/verify-generated-links.py "$generation" \
  --map "/Users/example/public-dotfiles=$repo_root"
python3 scripts/test-agent-status.py
python3 scripts/test-macos-settings.py
python3 scripts/test-nvim-health.py
python3 scripts/test-provenance.py
python3 scripts/test-retention.py
python3 scripts/test-public-control.py "$generation"
"$check_python" scripts/test-activation-guards.py "$generation"
PATH="$generation/home-path/bin:$PATH" "$check_python" scripts/test-tmux-recovery.py
task --taskfile global/Taskfile.yml --list-all >/dev/null

printf 'public dotfiles check passed\n'
