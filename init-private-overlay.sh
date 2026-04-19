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
default_private_repo="$(cd "$repo_root/.." && pwd -P)/private-config"
target="${PRIVATE_REPO_DIR:-$default_private_repo}"
template_root="$repo_root/templates/private-overlay"

if [[ ! -d "$template_root" ]]; then
  die "missing template directory: $template_root"
fi

if [[ -e "$target" && ! -d "$target" ]]; then
  die "target exists and is not a directory: $target"
fi

if [[ -d "$target" && -f "$target/install.sh" && -f "$target/private-paths.txt" ]]; then
  printf 'skip private overlay scaffold (already exists: %s)\n' "$target"
  exit 0
fi

if [[ -d "$target" && -n "$(find "$target" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  die "target directory is not empty: $target"
fi

mkdir -p "$target"
cp -R "$template_root/." "$target"
chmod +x "$target/install.sh"

if [[ ! -d "$target/.git" ]]; then
  git -C "$target" init -q
fi

printf 'private overlay scaffolded at %s\n' "$target"
printf 'next: add files to %s, track them with git, then run task install\n' "$target"
