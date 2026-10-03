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
nix_cmd flake check --no-write-lock-file
generation="$(nix_cmd build --no-link --print-out-paths .#homeConfigurations.example.activationPackage)"
python3 scripts/verify-generated-links.py "$generation" \
  --map "/Users/example/public-dotfiles=$repo_root"
python3 scripts/test-agent-status.py
python3 scripts/test-macos-settings.py
python3 scripts/test-nvim-health.py
python3 scripts/test-provenance.py
python3 scripts/test-public-control.py "$generation"
task --taskfile global/Taskfile.yml --list-all >/dev/null

printf 'public dotfiles check passed\n'
