#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

nix_cmd() {
  nix --extra-experimental-features "nix-command flakes" "$@"
}

run_first_available() {
  local found=0
  local -a candidates args

  while [ "$#" -gt 0 ]; do
    if [ "$1" = "--" ]; then
      shift
      args=("$@")
      break
    fi
    candidates+=("$1")
    shift
  done

  local command_path
  for command_path in "${candidates[@]}"; do
    if command -v "$command_path" >/dev/null 2>&1 || [ -x "$command_path" ]; then
      "$command_path" "${args[@]}"
      found=1
      break
    fi
  done

  if [ "$found" -eq 0 ]; then
    printf 'missing command candidate: %s\n' "${candidates[*]}" >&2
    return 127
  fi
}

verify_ghostty() {
  run_first_available \
    ghostty \
    /Applications/Ghostty.app/Contents/MacOS/ghostty \
    -- +validate-config
}

verify_karabiner_lint() {
  local file
  for file in .config/karabiner/assets/complex_modifications/*.json; do
    run_first_available \
      karabiner_cli \
      /opt/homebrew/bin/karabiner_cli \
      /usr/local/bin/karabiner_cli \
      "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli" \
      -- --lint-complex-modifications "$file"
  done
}

verify_karabiner_terminal_invariants() {
  ruby <<'RUBY'
require "json"

paths = [
  ".config/karabiner/assets/complex_modifications/xjm-rules.json",
  ".config/karabiner/karabiner.json",
]

def each_object(value, &block)
  case value
  when Hash
    yield value
    value.each_value { |child| each_object(child, &block) }
  when Array
    value.each { |child| each_object(child, &block) }
  end
end

def has_values?(value, *required)
  values = Array(value)
  required.all? { |item| values.include?(item) }
end

def limited_to_chrome?(item)
  Array(item["conditions"]).any? do |condition|
    condition.is_a?(Hash) &&
      condition["type"] == "frontmost_application_if" &&
      condition["bundle_identifiers"] == ["^com\\.google\\.Chrome$"]
  end
end

paths.each do |path|
  value = JSON.parse(File.read(path))
  each_object(value) do |item|
    source = item["from"]
    targets = item["to"]
    next unless source.is_a?(Hash) && targets.is_a?(Array)

    source_key = source["key_code"]
    next unless %w[h l].include?(source_key)
    next unless has_values?(source.dig("modifiers", "mandatory"), "control")

    targets.each do |target|
      next unless target.is_a?(Hash)
      target_key = target["key_code"]
      rewrites_terminal_tab =
        (source_key == "h" && target_key == "open_bracket") ||
        (source_key == "l" && target_key == "close_bracket")
      next unless rewrites_terminal_tab
      next unless has_values?(target["modifiers"], "command", "shift")
      next if limited_to_chrome?(item)

      warn "Karabiner rewrites Ctrl-#{source_key} in #{path}"
      exit 1
    end
  end
end
RUBY
}

verify_tmux() {
  local socket="public-dotfiles-verify-terminal-$$"
  local generation home_files tmux_config

  cleanup() {
    tmux -L "public-dotfiles-verify-terminal-$$" kill-server >/dev/null 2>&1 || true
  }
  trap cleanup EXIT

  activation_attr="$("$repo_root/scripts/home-config-attr.sh" activation-package)"
  generation="$(nix_cmd build --no-link --print-out-paths "$activation_attr")"
  home_files="$(readlink "$generation/home-files")"
  tmux_config="$home_files/.config/tmux/tmux.conf"

  tmux -L "$socket" -f /dev/null new-session -d -s verify-terminal 'sleep 60'
  tmux -L "$socket" source-file "$tmux_config"

  local key
  for key in M-b M-d M-D M-f M-w M-z; do
    if tmux -L "$socket" list-keys -T root "$key" >/dev/null 2>&1; then
      printf 'unexpected root tmux binding claims %s\n' "$key" >&2
      tmux -L "$socket" list-keys -T root "$key" >&2
      exit 1
    fi
  done

  tmux -L "$socket" list-keys -T prefix '|' >/dev/null
  tmux -L "$socket" list-keys -T prefix '_' >/dev/null
  tmux -L "$socket" list-keys -T prefix X >/dev/null
  tmux -L "$socket" list-keys -T prefix z >/dev/null
  tmux -L "$socket" list-keys -T prefix E >/dev/null
  tmux -L "$socket" list-keys -T prefix J | grep -q 'easyjump.tmux/easyjump.py'

  local table
  for table in copy-mode copy-mode-vi; do
    if tmux -L "$socket" list-keys -T "$table" C-J >/dev/null 2>&1; then
      printf 'unexpected EasyJump copy-mode binding in %s C-J\n' "$table" >&2
      tmux -L "$socket" list-keys -T "$table" C-J >&2
      exit 1
    fi
    tmux -L "$socket" list-keys -T "$table" C-j | grep -q 'select-pane -D'
  done
}

verify_ghostty
verify_karabiner_lint
verify_karabiner_terminal_invariants
verify_tmux

echo "terminal workflow verified"
