#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
home_root="${HOME}"
backup_root="$repo_root/.install-backups/$(date +%Y%m%d-%H%M%S)"
mode="symlink"
dry_run=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [--copy] [--dry-run]
EOF
}

for arg in "$@"; do
  case "$arg" in
    --copy) mode="copy" ;;
    --dry-run) dry_run=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage >&2
      exit 1
      ;;
  esac
done

run() {
  if [[ "$dry_run" -eq 1 ]]; then
    printf '[dry-run] %s\n' "$*"
    return 0
  fi
  "$@"
}

backup_target() {
  local target="$1"
  local rel="${target#"$home_root"/}"
  local backup_path="$backup_root/$rel"
  run mkdir -p "$(dirname "$backup_path")"
  run mv "$target" "$backup_path"
}

install_entry() {
  local rel="$1"
  local src="$repo_root/$rel"
  local dst="$home_root/$rel"

  run mkdir -p "$(dirname "$dst")"

  if [[ -L "$dst" ]]; then
    local linked_to
    linked_to="$(readlink "$dst")"
    if [[ "$linked_to" == "$src" ]]; then
      printf 'skip %s\n' "$rel"
      return 0
    fi
    backup_target "$dst"
  elif [[ -e "$dst" ]]; then
    backup_target "$dst"
  fi

  if [[ "$mode" == "copy" ]]; then
    if [[ -d "$src" ]]; then
      run cp -R "$src" "$dst"
    else
      run cp "$src" "$dst"
    fi
    printf 'copy %s\n' "$rel"
    return 0
  fi

  run ln -s "$src" "$dst"
  printf 'link %s\n' "$rel"
}

entries=(
  ".bash_profile"
  ".bashrc"
  ".claude-theme-sync.sh"
  ".config/.oh-my-posh.json"
  ".config/amethyst"
  ".config/bat"
  ".config/fish"
  ".config/ghostty"
  ".config/helix"
  ".config/joshuto"
  ".config/lazydocker"
  ".config/lazygit"
  ".config/nushell"
  ".config/nvim"
  ".config/ranger"
  ".config/skhd"
  ".config/starship.toml"
  ".config/taskell"
  ".config/yazi"
  ".config/zed"
  ".config/zellij"
  ".hushlogin"
  ".ideavimrc"
  ".p10k.zsh"
  ".procs.toml"
  ".profile"
  ".skhdrc"
  ".tmux-catppuccin-theme-sync.sh"
  ".tmux.conf"
  ".vim"
  ".vimrc"
  ".yabairc"
  ".zlogin"
  ".zprofile"
  ".zsh"
  ".zshrc"
  "Library/Application Support/abnerworks.Typora"
  "Library/Application Support/lazygit"
)

for entry in "${entries[@]}"; do
  install_entry "$entry"
done

if [[ "$dry_run" -eq 0 && -d "$backup_root" ]]; then
  printf 'backup %s\n' "$backup_root"
fi
