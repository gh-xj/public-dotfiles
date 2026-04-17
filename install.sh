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


warn_tmux_legacy_state() {
  local local_tmux="$home_root/.tmux.local.conf"
  local legacy_sync="$home_root/.tmux-catppuccin-theme-sync.sh"

  if [[ -f "$local_tmux" ]] && grep -q "tmux-catppuccin-theme-sync" "$local_tmux"; then
    printf 'warn %s\n' "~/.tmux.local.conf still references tmux-catppuccin-theme-sync.sh"
  fi

  if [[ -e "$legacy_sync" ]]; then
    printf 'warn %s\n' "~/.tmux-catppuccin-theme-sync.sh is legacy and no longer used by shared tmux config"
  fi
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
  ".claude/CLAUDE.md"
  ".claude/hooks"
  ".claude/settings.json"
  ".claude/statusline-command.sh"
  ".config/amethyst"
  ".config/bat"
  ".config/ghostty"
  ".config/karabiner"
  ".config/lazydocker"
  ".config/lazygit"
  ".config/nvim"
  ".config/starship.toml"
  ".config/yazi"
  ".codex/AGENTS.md"
  ".codex/rules"
  ".hushlogin"
  ".tmux.conf"
  ".zlogin"
  ".zprofile"
  ".zsh"
  ".zshrc"
  "Library/Application Support/abnerworks.Typora"
  "Library/Application Support/com.pais.handy/settings_store.json"
  "Library/Application Support/lazygit"
)

# Merge top-level key=value settings from the dotfiles baseline into the live
# ~/.codex/config.toml without clobbering project-trust entries that Codex
# writes back dynamically.  Sections ([tui], [features], etc.) are left alone
# because Codex also owns those.
merge_codex_config() {
  local src="$repo_root/.codex/config.toml"
  local dst="$home_root/.codex/config.toml"

  run mkdir -p "$(dirname "$dst")"

  if [[ ! -f "$dst" ]]; then
    run cp "$src" "$dst"
    printf 'copy %s\n' ".codex/config.toml"
    return 0
  fi

  local -a to_prepend=()
  local in_section=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^\[.*\] ]]; then
      in_section=1
    elif [[ "$in_section" -eq 0 && "$line" =~ ^[a-z_]+[[:space:]]*=.* ]]; then
      local key="${line%%=*}"
      key="${key%%+([[:space:]])}"
      key="${key%% }"
      if ! grep -q "^${key}[[:space:]]*=" "$dst"; then
        to_prepend+=("$line")
      fi
    fi
  done < "$src"

  if [[ ${#to_prepend[@]} -gt 0 ]]; then
    if [[ "$dry_run" -eq 0 ]]; then
      local tmp
      tmp="$(mktemp)"
      printf '%s\n' "${to_prepend[@]}" > "$tmp"
      printf '\n' >> "$tmp"
      cat "$dst" >> "$tmp"
      mv "$tmp" "$dst"
    fi
    printf 'merge .codex/config.toml (%d settings injected)\n' "${#to_prepend[@]}"
  else
    printf 'skip %s\n' ".codex/config.toml"
  fi
}

for entry in "${entries[@]}"; do
  install_entry "$entry"
done

merge_codex_config

warn_tmux_legacy_state

if [[ "$dry_run" -eq 0 && -d "$backup_root" ]]; then
  printf 'backup %s\n' "$backup_root"
fi
