#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

runs="${SHELL_BENCH_RUNS:-10}"
warmup="${SHELL_BENCH_WARMUP:-3}"

usage() {
  cat <<'EOF'
Usage: task shell:bench -- [--runs N] [--warmup N]

Environment:
  SHELL_BENCH_RUNS=N    Number of hyperfine runs, default 10.
  SHELL_BENCH_WARMUP=N  Number of hyperfine warmups, default 3.
EOF
}

while (($#)); do
  case "$1" in
    --runs)
      runs="${2:?--runs requires a value}"
      shift 2
      ;;
    --warmup)
      warmup="${2:?--warmup requires a value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'unknown argument: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$1" >&2
    exit 127
  }
}

need_cmd hyperfine
need_cmd zsh

printf '== zsh startup ==\n'
hyperfine --warmup "$warmup" --runs "$runs" \
  'zsh -f -i -c exit' \
  'zsh -c exit' \
  'zsh -i -c exit' \
  'ZSH_FAST=1 zsh -i -c exit' \
  'ZSH_FAST=1 ZSH_FAST_HISTORY=1 zsh -i -c exit' \
  'ZSH_MINIMAL=1 zsh -i -c exit' \
  'zsh -l -i -c exit'

component_cmds=(
  'zsh -f -c "source $HOME/.zshenv"'
  'zsh -f -i -c "autoload -Uz compinit; compinit -C -d $HOME/.zcompdump"'
)

if [[ -r "$HOME/.cache/starship-init.zsh" ]]; then
  component_cmds+=('zsh -f -c "source $HOME/.cache/starship-init.zsh"')
fi

if command -v zoxide >/dev/null 2>&1; then
  component_cmds+=('zoxide init zsh --cmd j >/dev/null')
fi

printf '\n== shell init components ==\n'
hyperfine --warmup "$warmup" --runs "$runs" "${component_cmds[@]}"

printf '\n== zinit deferred plugins ==\n'
printf '%s\n' "Open a normal interactive shell, wait for the first prompt to settle, then run: zinit times"
