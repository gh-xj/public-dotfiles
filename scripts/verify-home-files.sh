#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

nix_cmd() {
  nix --extra-experimental-features "nix-command flakes" "$@"
}

generation="$(nix_cmd build --no-link --print-out-paths .#homeConfigurations.example.activationPackage)"
home_files="$(readlink "$generation/home-files")"

assert_file() {
  local path="$1"
  if [ ! -e "$home_files/$path" ]; then
    printf 'missing generated Home Manager file: %s\n' "$path" >&2
    exit 1
  fi
}

assert_line() {
  local path="$1"
  local expected="$2"
  assert_file "$path"
  if ! grep -Fx -- "$expected" "$home_files/$path" >/dev/null; then
    printf 'missing expected line in %s: %s\n' "$path" "$expected" >&2
    exit 1
  fi
}

assert_file ".amethyst.yml"
assert_file ".config/amethyst/amethyst.yml"
assert_file ".config/bat/config"
assert_file ".config/ghostty/config"
assert_file ".config/karabiner/karabiner.json"
assert_file ".config/lazygit/config.yml"
assert_file ".config/nvim/init.lua"
assert_file ".config/opencode/opencode.json"
assert_file ".config/starship.toml"
assert_file ".config/yazi/yazi.toml"
assert_file ".tmux.conf"
assert_file ".zprofile"
assert_file ".zshrc"

assert_line ".config/ghostty/config" "font-family = RecMonoDuotone Nerd Font"
assert_line ".config/ghostty/config" "theme = light:Atom One Light,dark:One Dark Two"

echo "home file baseline verified"
