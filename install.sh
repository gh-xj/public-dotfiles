#!/usr/bin/env bash
set -euo pipefail

script_name="$(basename "$0")"
invocation_path="${BASH_SOURCE[0]}"

resolve_repo_root() {
  local script_dir git_root

  if [[ -L "$invocation_path" ]]; then
    return 1
  fi

  script_dir="$(cd "$(dirname "$invocation_path")" && pwd -P)" || return 1
  git_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null)" || return 1

  if [[ "$git_root" != "$script_dir" ]]; then
    return 1
  fi

  git -C "$git_root" ls-files --error-unmatch install.sh README.md >/dev/null 2>&1 || return 1

  printf '%s\n' "$git_root"
}

die() {
  printf '%s: %s\n' "$script_name" "$1" >&2
  exit 1
}

repo_root="$(resolve_repo_root)" || die "must be run from the repo checkout root"

home_root="${HOME}"
backup_root="$repo_root/.install-backups/$(date +%Y%m%d-%H%M%S)"
mode="symlink"
dry_run=0

usage() {
  cat <<EOF
Usage: $script_name [--copy] [--dry-run] [--help]

Options:
  --copy     copy files instead of creating symlinks
  --dry-run  print actions without changing the filesystem
  -h, --help show this help text
EOF
}

while (($#)); do
  case "$1" in
    --copy) mode="copy" ;;
    --dry-run) dry_run=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unsupported argument: $1"
      ;;
  esac
  shift
done

run() {
  if [[ "$dry_run" -eq 1 ]]; then
    printf '[dry-run] %s\n' "$*"
    return 0
  fi
  "$@"
}

ensure_tmux_catppuccin() {
  local plugin_root="$home_root/.config/tmux/plugins/catppuccin"
  local plugin_repo="$plugin_root/tmux"
  local plugin_url="https://github.com/catppuccin/tmux.git"

  run mkdir -p "$plugin_root"

  if [[ -d "$plugin_repo/.git" ]]; then
    run git -C "$plugin_repo" pull --ff-only
    printf 'update %s\n' ".config/tmux/plugins/catppuccin/tmux"
    return 0
  fi

  if [[ -e "$plugin_repo" ]]; then
    backup_target "$plugin_repo"
  fi

  run git clone "$plugin_url" "$plugin_repo"
  printf 'clone %s\n' ".config/tmux/plugins/catppuccin/tmux"
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
  ".config/karabiner"
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

ensure_tmux_catppuccin

if [[ "$dry_run" -eq 0 && -d "$backup_root" ]]; then
  printf 'backup %s\n' "$backup_root"
fi
