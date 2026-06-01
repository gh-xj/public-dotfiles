#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
taskfile="$repo_root/global/Taskfile.yml"
live=0

usage() {
  cat <<'USAGE'
Usage: verify-global-taskfile.sh [--live]

Verifies the public go-task global Taskfile source.
With --live, verifies the Home Manager-linked global Taskfile paths.
USAGE
}

case "${1:-}" in
  "")
    ;;
  --live)
    live=1
    taskfile="$HOME/Taskfile.yml"
    ;;
  --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

resolve_final() {
  local path="$1"
  local target dir

  while [ -L "$path" ]; do
    target="$(readlink "$path")"
    case "$target" in
      /*)
        path="$target"
        ;;
      *)
        dir="$(cd -- "$(dirname -- "$path")" && pwd)"
        path="$dir/$target"
        ;;
    esac
  done

  printf '%s\n' "$path"
}

if [ ! -f "$taskfile" ]; then
  printf 'missing global Taskfile: %s\n' "$taskfile" >&2
  exit 1
fi

if grep -nE '(private-config|xj-private|bytedance|ByteDance|token|secret|password|api[_-]?key|oauth|bearer|Authorization|/Users/xj|/Users/bytedance)' "$taskfile" >/dev/null; then
  printf '%s contains private/sensitive-looking strings\n' "$taskfile" >&2
  exit 1
fi

task --taskfile "$taskfile" --list-all | grep -F 'new-human-req-doc' >/dev/null
task --taskfile "$taskfile" --list-all | grep -F 'help' >/dev/null

if [ "$live" -eq 1 ]; then
  expected="$HOME/public-dotfiles/global/Taskfile.yml"
  live_path="$HOME/Taskfile.yml"
  if [ ! -e "$live_path" ] && [ ! -L "$live_path" ]; then
    printf 'missing live global Taskfile path: %s\n' "$live_path" >&2
    exit 1
  fi
  actual="$(resolve_final "$live_path")"
  if [ "$actual" != "$expected" ]; then
    printf 'unexpected live global Taskfile target for %s: expected %s got %s\n' \
      "$live_path" "$expected" "$actual" >&2
    exit 1
  fi
  task -g --list-all | grep -F 'new-human-req-doc' >/dev/null
fi

printf 'global Taskfile baseline verified\n'
