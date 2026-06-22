#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

nix_cmd() {
  nix --extra-experimental-features "nix-command flakes" "$@"
}

activation_attr="$("$repo_root/scripts/home-config-attr.sh" activation-package)"
generation="$(nix_cmd build --no-link --print-out-paths "$activation_attr")"
home_files="$(readlink "$generation/home-files")"

assert_file() {
  local path="$1"
  if [ ! -e "$home_files/$path" ] && [ ! -L "$home_files/$path" ]; then
    printf 'missing generated Home Manager file: %s\n' "$path" >&2
    exit 1
  fi
}

assert_symlink_target() {
  local path="$1"
  local expected="$2"
  local actual final

  assert_file "$path"
  actual="$(readlink "$home_files/$path" 2>/dev/null || true)"
  final="$(readlink "$actual" 2>/dev/null || printf '%s' "$actual")"
  if [ "$final" != "$expected" ]; then
    printf 'unexpected generated link target for %s: expected %s got %s\n' "$path" "$expected" "$final" >&2
    exit 1
  fi
}

assert_target_prefix() {
  local path="$1"
  local expected_prefix="$2"
  local final

  assert_file "$path"
  final="$(realpath "$home_files/$path")"
  case "$final" in
    "$expected_prefix"*)
      ;;
    *)
      printf 'unexpected generated link target prefix for %s: expected prefix %s got %s\n' "$path" "$expected_prefix" "$final" >&2
      exit 1
      ;;
  esac
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
assert_file ".config/amethyst"
assert_file ".config/bat/config"
assert_file ".config/ghostty/config"
assert_file ".config/karabiner"
assert_file ".config/lazygit/config.yml"
assert_file ".config/nvim"
assert_file ".config/opencode"
assert_file ".config/raycast/scripts"
assert_file ".config/starship.toml"
assert_file ".config/xj_public_raycast_scripts"
assert_file ".config/yazi/yazi.toml"
assert_file ".local/bin/apply_patch"
assert_file ".local/bin/patchkit"
assert_file ".tmux.conf"
assert_file "Taskfile.yml"
assert_file ".zshenv"
assert_file ".zprofile"
assert_file ".zshrc"

assert_symlink_target ".config/amethyst" "/Users/example/public-dotfiles/.config/amethyst"
assert_symlink_target ".config/karabiner" "/Users/example/public-dotfiles/.config/karabiner"
assert_symlink_target ".config/nvim" "/Users/example/public-dotfiles/.config/nvim"
assert_symlink_target ".config/opencode" "/Users/example/public-dotfiles/.config/opencode"
assert_symlink_target ".config/raycast/scripts" "/Users/example/public-dotfiles/.config/raycast/scripts"
assert_symlink_target ".config/xj_public_raycast_scripts" "/Users/example/public-dotfiles/.config/raycast/scripts"
assert_symlink_target ".amethyst.yml" "/Users/example/public-dotfiles/.config/amethyst/amethyst.yml"
assert_symlink_target "Taskfile.yml" "/Users/example/public-dotfiles/global/Taskfile.yml"
assert_symlink_target ".local/bin/apply_patch" "/Users/example/public-dotfiles/scripts/patchkit"
assert_symlink_target ".local/bin/patchkit" "/Users/example/public-dotfiles/scripts/patchkit"
assert_symlink_target ".zshenv" "/Users/example/public-dotfiles/.zshenv"
assert_symlink_target ".zprofile" "/Users/example/public-dotfiles/.zprofile"
assert_symlink_target ".zshrc" "/Users/example/public-dotfiles/.zshrc"

assert_target_prefix ".config/bat/config" "/nix/store/"
assert_target_prefix ".config/lazygit/config.yml" "/nix/store/"
assert_target_prefix ".config/starship.toml" "/nix/store/"
assert_target_prefix ".config/yazi/yazi.toml" "/nix/store/"
assert_target_prefix ".claude/CLAUDE.md" "/nix/store/"
assert_target_prefix ".claude/settings.json" "/nix/store/"
assert_target_prefix ".claude/statusline-command.sh" "/nix/store/"
assert_target_prefix ".codex/AGENTS.md" "/nix/store/"
assert_target_prefix ".codex/rules" "/nix/store/"

assert_line ".config/ghostty/config" "font-family = RecMonoDuotone Nerd Font"
assert_line ".config/ghostty/config" "theme = light:Atom One Light,dark:One Dark Two"

echo "home file baseline verified"
