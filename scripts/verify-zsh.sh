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

nix_cmd() {
  nix --extra-experimental-features "nix-command flakes" "$@"
}

need_cmd zsh

zsh -n "$repo_root/.zshenv"
zsh -n "$repo_root/.zshrc"
zsh -n "$repo_root/.zprofile"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

home_dir="$tmpdir/home"
mkdir -p "$home_dir/.cache" "$home_dir/.config" "$home_dir/.ssh/includes"

cat > "$home_dir/.ssh/config" <<'EOF'
Include ~/.ssh/includes/*.conf

Host *
  AddKeysToAgent yes

Host unit-main main-alias 10.0.0.10
  HostName main.example.test

Host wildcard-*
  HostName ignored.example.test
EOF

cat > "$home_dir/.ssh/includes/extra.conf" <<'EOF'
Host unit-include
  HostName include.example.test
EOF

cat > "$home_dir/.ssh/known_hosts" <<'EOF'
known-host.example ssh-ed25519 AAA
[known-port-host]:2222 ssh-ed25519 BBB
|1|hashed|entry ssh-ed25519 CCC
EOF

plugin_paths_file="$tmpdir/plugin-paths.zsh"
shell_tools_path=""

if command -v nix >/dev/null 2>&1; then
  activation_attr="$("$repo_root/scripts/home-config-attr.sh" activation-package)"
  config_attr="$("$repo_root/scripts/home-config-attr.sh" config)"
  shell_tools_path="$(nix_cmd build --no-link --print-out-paths .#shellTools)"
  nix_cmd build --no-link "$activation_attr" >/dev/null
  nix_cmd eval --raw "$config_attr" \
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

profile_probe="$(
  REPO_ROOT="$repo_root" \
  HOME="$home_dir" \
  TERMINFO="/missing/terminfo" \
  TERMINFO_DIRS="/missing/terminfo:/usr/share/terminfo" \
  zsh -f -c '
source "$REPO_ROOT/.zprofile"
missing=0
for dir in ${(s.:.)TERMINFO_DIRS}; do
  [[ -d "$dir" ]] || missing=1
done
printf "terminfo-dirs-existing=%s\n" "$(( 1 - missing ))"
if [[ -z "${TERMINFO:-}" ]]; then
  printf "terminfo-unset=1\n"
else
  printf "terminfo-unset=0\n"
fi
'
)"

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
printf "fzf-file-widget=%s\n" "$+widgets[fzf-file-widget]"
printf "fzf-cd-widget=%s\n" "$+widgets[fzf-cd-widget]"
if bindkey -M viins "^T" | grep -q "fzf-file-widget"; then
  printf "fzf-ctrl-t-binding=1\n"
else
  printf "fzf-ctrl-t-binding=0\n"
fi
if bindkey -M viins "\ec" | grep -q "fzf-cd-widget"; then
  printf "fzf-alt-c-binding=1\n"
else
  printf "fzf-alt-c-binding=0\n"
fi
printf "fzf-tab-widget=%s\n" "$+widgets[fzf-tab-complete]"
if bindkey "^I" | grep -q "fzf-tab-complete"; then
  printf "fzf-tab-binding=1\n"
else
  printf "fzf-tab-binding=0\n"
fi
if zstyle -L | grep -q "_xj_ssh_completion_hosts_style"; then
  printf "ssh-host-style=1\n"
else
  printf "ssh-host-style=0\n"
fi
reply=()
_xj_ssh_completion_hosts_style
if print -lr -- "${reply[@]}" | grep -qx "unit-main"; then
  printf "ssh-config-host=1\n"
else
  printf "ssh-config-host=0\n"
fi
if print -lr -- "${reply[@]}" | grep -qx "unit-include"; then
  printf "ssh-include-host=1\n"
else
  printf "ssh-include-host=0\n"
fi
if print -lr -- "${reply[@]}" | grep -qx "known-host.example"; then
  printf "ssh-known-host=1\n"
else
  printf "ssh-known-host=0\n"
fi
if print -lr -- "${reply[@]}" | grep -qx "wildcard-\\*"; then
  printf "ssh-wildcard-filtered=0\n"
else
  printf "ssh-wildcard-filtered=1\n"
fi
printf "atuin-widget=%s\n" "$+widgets[atuin-search]"
if bindkey -M viins "^R" | grep -q "atuin-search"; then
  printf "atuin-ctrl-r-binding=1\n"
else
  printf "atuin-ctrl-r-binding=0\n"
fi
printf "starship-prompt=%s\n" "$+functions[prompt_starship_precmd]"
'
)"

printf '%s\n' "$profile_probe"
printf '%s\n' "$probe"

require_probe() {
  local key="$1"
  local want="$2"

  if ! printf '%s\n' "$profile_probe"$'\n'"$probe" | grep -qx "${key}=${want}"; then
    printf 'zsh contract failed: expected %s=%s\n' "$key" "$want" >&2
    exit 1
  fi
}

require_probe terminfo-dirs-existing 1
require_probe terminfo-unset 1
require_probe plugin-paths-generated 1
require_probe zinit 0
require_probe zsh-vi-mode 1
require_probe autosuggestions 1
require_probe syntax-highlighting 1
require_probe autopair-widget 1
require_probe fzf-file-widget 1
require_probe fzf-cd-widget 1
require_probe fzf-ctrl-t-binding 1
require_probe fzf-alt-c-binding 1
require_probe fzf-tab-widget 1
require_probe fzf-tab-binding 1
require_probe ssh-host-style 1
require_probe ssh-config-host 1
require_probe ssh-include-host 1
require_probe ssh-known-host 1
require_probe ssh-wildcard-filtered 1
require_probe atuin-widget 1
require_probe atuin-ctrl-r-binding 1
require_probe starship-prompt 1
