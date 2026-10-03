#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
generation="${1:?usage: verify-zsh.sh GENERATION}"
home_files="$(realpath "$generation/home-files")"
plugin_paths="$home_files/.config/xj/zsh/plugin-paths.zsh"

zsh -n "$repo_root/.zshenv"
zsh -n "$repo_root/.zprofile"
zsh -n "$repo_root/.zshrc"
python3 "$repo_root/scripts/test-codex-tmux.py"

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

home_dir="$tmpdir/home"
mkdir -p "$home_dir/.cache" "$home_dir/.config/zsh" "$home_dir/.local/state/nix/profiles"
ln -s "$generation" "$home_dir/.local/state/nix/profiles/home-manager"
printf 'export PRIVATE_ENV_FIXTURE=loaded\n' >"$home_dir/.config/zsh/private.zshenv"
expected_path="$home_dir/.local/bin:$home_dir/.local/share/mise/shims:$home_dir/.local/state/nix/profiles/home-manager/home-path/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

REPO_ROOT="$repo_root" \
HOME="$home_dir" \
XDG_CONFIG_HOME="$home_dir/.config" \
XDG_STATE_HOME="$home_dir/.local/state" \
XJ_ZSH_PLUGIN_PATHS_FILE="$plugin_paths" \
XJ_ZSH_DISABLE_LEGACY_PLUGIN_CACHE=1 \
EXPECTED_PATH="$expected_path" \
TERM="xterm-256color" \
zsh -dfi -c '
  # Keep the absolute macOS hook isolated from the real GUI session.
  function /bin/launchctl() { return 0; }
  source "$REPO_ROOT/.zshenv"
  source "$REPO_ROOT/.zprofile"
  source "$REPO_ROOT/.zshrc"
  [[ "$PRIVATE_ENV_FIXTURE" == loaded ]]
  [[ "$PATH" == "$EXPECTED_PATH" ]]
  [[ "$(command -v yazi)" == "$HOME/.local/state/nix/profiles/home-manager/home-path/bin/yazi" ]]
  [[ "$(command -v ya)" == "$HOME/.local/state/nix/profiles/home-manager/home-path/bin/ya" ]]
  [[ "$(command -v mise)" == "$HOME/.local/state/nix/profiles/home-manager/home-path/bin/mise" ]]
  [[ "$XJ_ZSH_PLUGIN_PATHS_GENERATED" == 1 ]]
  (( $+functions[zvm_select_vi_mode] ))
  (( $+functions[_zsh_autosuggest_start] ))
  (( $+functions[_zsh_highlight] ))
  (( $+widgets[fzf-file-widget] ))
  [[ -o promptsubst ]]
  print -P -- "$PROMPT" >/dev/null
'

REPO_ROOT="$repo_root" HOME="$home_dir" EXPECTED_PATH="$expected_path" \
  zsh -df -c '
    source "$REPO_ROOT/.zshenv"
    [[ "$PATH" == "$EXPECTED_PATH" ]]
    [[ "$(command -v yazi)" == "$HOME/.local/state/nix/profiles/home-manager/home-path/bin/yazi" ]]
    [[ "$(command -v ya)" == "$HOME/.local/state/nix/profiles/home-manager/home-path/bin/ya" ]]
  '
printf 'zsh startup, identical PATH and active Home Manager CLI precedence verified\n'
