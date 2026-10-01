#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != "--deep" ]; }; then
  printf 'usage: %s [--deep]\n' "$0" >&2
  exit 2
fi
deep=0
if [ "${1:-}" = "--deep" ]; then
  deep=1
fi

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

nix_cmd() {
  nix --extra-experimental-features "nix-command flakes" "$@"
}

gitleaks protect --staged --source . --redact --no-banner
./scripts/verify-denylist.sh
python3 scripts/verify-zed.py

generation="$(nix_cmd build --no-link --print-out-paths .#)"
home_files="$(realpath "$generation/home-files")"
python3 scripts/verify-generated-links.py "$home_files" "$repo_root"
"$generation/home-path/bin/default-openers" validate

case "$(uname -m)" in
  arm64) home_config="example" ;;
  x86_64) home_config="example-x86_64" ;;
  *)
    printf 'unsupported Darwin architecture: %s\n' "$(uname -m)" >&2
    exit 1
    ;;
esac
./scripts/verify-zsh.sh "$generation"
bash ./scripts/verify-nvim.sh
./scripts/verify-terminal.sh "$generation"
python3 scripts/test-agent-status.py
python3 scripts/test-public-control.py
python3 scripts/test-workspace-health.py
PATH="$generation/home-path/bin:$PATH" python3 scripts/test-human-req-doc.py
"$generation/home-path/bin/tmux-recovery" --help >/dev/null
"$generation/home-path/bin/agent-workspace" doctor --help >/dev/null
python3 scripts/verify-codex-strict.py
task --taskfile global/Taskfile.yml --list-all >/dev/null

if [ "$deep" -eq 1 ]; then
  python3 scripts/verify-agent-seeds.py "$generation" "$repo_root" ".#homeConfigurations.$home_config"
  python3 scripts/test-ghostty-migration.py "$generation" ".#homeConfigurations.$home_config"
  python3 scripts/test-yazi-runtime.py "$generation"
  python3 scripts/test-yazi-projects.py "$generation/home-path/bin/yazi"
  PATH="$generation/home-path/bin:$PATH" python3 scripts/test-tmux-recovery.py
  python3 scripts/test-downstream.py "$generation"
  python3 scripts/probe-codex-rules.py

  bootstrap_root="$(mktemp -d)"
  cleanup() {
    rm -rf "$bootstrap_root"
  }
  trap cleanup EXIT
  XJ_PUBLIC_DOTFILES_BOOTSTRAP_DIR="$bootstrap_root" \
    ./scripts/bootstrap-macos.sh --darwin --dry-run --skip-build
  nix_cmd eval --raw \
    "$bootstrap_root/${USER:-$(id -un)}#darwinConfigurations.bootstrap.config.system.build.toplevel.drvPath" \
    >/dev/null
fi

printf 'public dotfiles check passed\n'
