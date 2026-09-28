#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
generation="${1:?usage: verify-zsh.sh GENERATION}"
home_files="$(realpath "$generation/home-files")"
plugin_paths="$home_files/.config/xj/zsh/plugin-paths.zsh"

zsh -n "$repo_root/.zshenv"
zsh -n "$repo_root/.zprofile"
zsh -n "$repo_root/.zshrc"

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

home_dir="$tmpdir/home"
mkdir -p "$home_dir/.cache" "$home_dir/.config/zsh"
printf 'export PRIVATE_ENV_FIXTURE=loaded\n' >"$home_dir/.config/zsh/private.zshenv"

REPO_ROOT="$repo_root" \
HOME="$home_dir" \
XDG_CONFIG_HOME="$home_dir/.config" \
XJ_ZSH_PLUGIN_PATHS_FILE="$plugin_paths" \
XJ_ZSH_DISABLE_LEGACY_PLUGIN_CACHE=1 \
PATH="$generation/home-path/bin:$PATH" \
TERM="xterm-256color" \
zsh -dfi -c '
  source "$REPO_ROOT/.zshenv"
  source "$REPO_ROOT/.zprofile"
  source "$REPO_ROOT/.zshrc"
  [[ "$PRIVATE_ENV_FIXTURE" == loaded ]]
  [[ "$XJ_ZSH_PLUGIN_PATHS_GENERATED" == 1 ]]
  (( $+functions[zvm_select_vi_mode] ))
  (( $+functions[_zsh_autosuggest_start] ))
  (( $+functions[_zsh_highlight] ))
  (( $+widgets[fzf-file-widget] ))
  [[ -o promptsubst ]]
  print -P -- "$PROMPT" >/dev/null
'

printf 'zsh startup verified\n'
