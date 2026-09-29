#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
generation="${1:?usage: verify-terminal.sh GENERATION}"

run_first_available() {
  local found=0
  local -a candidates args

  while [ "$#" -gt 0 ]; do
    if [ "$1" = "--" ]; then
      shift
      args=("$@")
      break
    fi
    candidates+=("$1")
    shift
  done

  local command_path
  for command_path in "${candidates[@]}"; do
    if command -v "$command_path" >/dev/null 2>&1 || [ -x "$command_path" ]; then
      "$command_path" "${args[@]}"
      found=1
      break
    fi
  done

  if [ "$found" -eq 0 ]; then
    printf 'missing command candidate: %s\n' "${candidates[*]}" >&2
    return 127
  fi
}

verify_ghostty() {
  run_first_available \
    ghostty \
    /Applications/Ghostty.app/Contents/MacOS/ghostty \
    -- +validate-config
}

verify_karabiner_lint() {
  local file
  for file in .config/karabiner/assets/complex_modifications/*.json; do
    run_first_available \
      karabiner_cli \
      /opt/homebrew/bin/karabiner_cli \
      /usr/local/bin/karabiner_cli \
      "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli" \
      -- --lint-complex-modifications "$file"
  done
}

verify_tmux() {
  local socket="public-dotfiles-verify-terminal-$$"
  local home_files tmux_config

  cleanup() {
    tmux -L "public-dotfiles-verify-terminal-$$" kill-server >/dev/null 2>&1 || true
  }
  trap cleanup EXIT

  home_files="$(realpath "$generation/home-files")"
  tmux_config="$home_files/.config/tmux/tmux.conf"

  tmux -L "$socket" -f /dev/null new-session -d -s verify-terminal 'sleep 60'
  tmux -L "$socket" source-file "$tmux_config"

  python3 "$repo_root/scripts/test-agent-panes.py" "$socket" "$generation/home-path/bin" "$home_files/.claude/statusline-command.sh"
}

verify_ghostty
verify_karabiner_lint
verify_tmux

echo "terminal workflow verified"
