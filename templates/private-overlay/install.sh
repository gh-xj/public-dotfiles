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

  printf '%s\n' "$git_root"
}

die() {
  printf '%s: %s\n' "$script_name" "$1" >&2
  exit 1
}

repo_root="$(resolve_repo_root)" || die "must be run from the repo checkout root"
manifest="$repo_root/private-paths.txt"
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

  if [[ ! -e "$src" ]]; then
    printf 'skip-missing %s\n' "$rel"
    return 0
  fi

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

[[ -f "$manifest" ]] || die "missing manifest: $manifest"

while IFS= read -r rel || [[ -n "$rel" ]]; do
  [[ -n "$rel" ]] || continue
  [[ "$rel" =~ ^# ]] && continue
  install_entry "$rel"
done < "$manifest"

if [[ "$dry_run" -eq 0 && -d "$backup_root" ]]; then
  printf 'backup %s\n' "$backup_root"
fi
