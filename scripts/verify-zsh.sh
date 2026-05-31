#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$1" >&2
    exit 127
  }
}

need_cmd zsh

zsh -n "$repo_root/.zshrc"
zsh -n "$repo_root/.zprofile"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

home_dir="$tmpdir/home"
mkdir -p "$home_dir/.cache" "$home_dir/.config"

plugin_paths_file="$tmpdir/plugin-paths.zsh"
shell_tools_path=""

if command -v nix >/dev/null 2>&1; then
  shell_tools_path="$(nix build --no-link --print-out-paths .#shellTools)"
  nix build --no-link .#homeConfigurations.example.activationPackage >/dev/null
  nix eval --raw '.#homeConfigurations.example' \
    --apply 'x: x.config.xdg.configFile."xj/zsh/plugin-paths.zsh".text' \
    > "$plugin_paths_file"
else
  live_plugin_paths="${XJ_ZSH_PLUGIN_PATHS_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/xj/zsh/plugin-paths.zsh}"
  if [[ ! -r "$live_plugin_paths" ]]; then
    printf 'missing nix and live zsh plugin path file: %s\n' "$live_plugin_paths" >&2
    exit 1
  fi
  cp "$live_plugin_paths" "$plugin_paths_file"
fi

if [[ -n "$shell_tools_path" ]]; then
  export PATH="$shell_tools_path/bin:$PATH"
fi

probe="$(
  REPO_ROOT="$repo_root" \
  HOME="$home_dir" \
  XDG_CONFIG_HOME="$home_dir/.config" \
  XJ_ZSH_PLUGIN_PATHS_FILE="$plugin_paths_file" \
  XJ_ZSH_DISABLE_LEGACY_PLUGIN_CACHE=1 \
  zsh -f -i -c '
source "$REPO_ROOT/.zshrc"
printf "plugin-paths-generated=%s\n" "${XJ_ZSH_PLUGIN_PATHS_GENERATED:-0}"
printf "zinit=%s\n" "$+functions[zinit]"
printf "zsh-vi-mode=%s\n" "$+functions[zvm_select_vi_mode]"
printf "autosuggestions=%s\n" "$+functions[_zsh_autosuggest_start]"
printf "syntax-highlighting=%s\n" "$+functions[_zsh_highlight]"
printf "autopair-widget=%s\n" "$+widgets[autopair-insert]"
printf "fzf-tab-widget=%s\n" "$+widgets[fzf-tab-complete]"
if bindkey "^I" | grep -q "fzf-tab-complete"; then
  printf "fzf-tab-binding=1\n"
else
  printf "fzf-tab-binding=0\n"
fi
printf "atuin-widget=%s\n" "$+widgets[atuin-search]"
printf "starship-prompt=%s\n" "$+functions[prompt_starship_precmd]"
'
)"

printf '%s\n' "$probe"

require_probe() {
  local key="$1"
  local want="$2"

  if ! printf '%s\n' "$probe" | grep -qx "${key}=${want}"; then
    printf 'zsh contract failed: expected %s=%s\n' "$key" "$want" >&2
    exit 1
  fi
}

require_probe plugin-paths-generated 1
require_probe zinit 0
require_probe zsh-vi-mode 1
require_probe autosuggestions 1
require_probe syntax-highlighting 1
require_probe autopair-widget 1
require_probe fzf-tab-widget 1
require_probe fzf-tab-binding 1
require_probe atuin-widget 1
require_probe starship-prompt 1
