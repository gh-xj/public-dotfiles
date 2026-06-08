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

assert_line() {
  local file="$1"
  local expected="$2"

  if ! grep -Fx -- "$expected" "$file" >/dev/null 2>&1; then
    printf 'missing expected line in %s: %s\n' "$file" "$expected" >&2
    exit 1
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
  local generation home_files tmux_config ghostty_config

  cleanup() {
    tmux -L "public-dotfiles-verify-terminal-$$" kill-server >/dev/null 2>&1 || true
  }
  trap cleanup EXIT

  activation_attr="$("$repo_root/scripts/home-config-attr.sh" activation-package)"
  generation="$(nix_cmd build --no-link --print-out-paths "$activation_attr")"
  home_files="$(readlink "$generation/home-files")"
  tmux_config="$home_files/.config/tmux/tmux.conf"
  ghostty_config="$home_files/.config/ghostty/config"

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

  local root_binding
  for root_binding in \
    "M-a|select-pane -t 1" \
    "M-s|select-pane -t 2" \
    "M-c|select-pane -t 3" \
    "M-e|select-pane -t 4" \
    "M-g|select-pane -t 5" \
    "M-i|select-pane -t 6" \
    "M-o|select-pane -t 7" \
    "M-p|select-pane -t 8" \
    "M-u|select-pane -t 9" \
    "M-y|select-pane -t :.#{window_panes}" \
    "M-1|select-window -t 1" \
    "M-2|select-window -t 2" \
    "M-3|select-window -t 3" \
    "M-4|select-window -t 4" \
    "M-5|select-window -t 5" \
    "M-6|select-window -t 6" \
    "M-7|select-window -t 7" \
    "M-8|select-window -t 8" \
    "M-9|select-window -t 9" \
    "M-0|select-window -t \"{end}\""
  do
    local key="${root_binding%%|*}"
    local expected="${root_binding#*|}"
    tmux -L "$socket" list-keys -T root "$key" | grep -Fq -- "$expected"
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

  assert_line "$ghostty_config" 'keybind = ctrl+digit_1=text:\x1ba'
  assert_line "$ghostty_config" 'keybind = ctrl+digit_2=text:\x1bs'
  assert_line "$ghostty_config" 'keybind = ctrl+digit_3=text:\x1bc'
  assert_line "$ghostty_config" 'keybind = ctrl+digit_4=text:\x1be'
  assert_line "$ghostty_config" 'keybind = ctrl+digit_5=text:\x1bg'
  assert_line "$ghostty_config" 'keybind = ctrl+digit_6=text:\x1bi'
  assert_line "$ghostty_config" 'keybind = ctrl+digit_7=text:\x1bo'
  assert_line "$ghostty_config" 'keybind = ctrl+digit_8=text:\x1bp'
  assert_line "$ghostty_config" 'keybind = ctrl+digit_9=text:\x1bu'
  assert_line "$ghostty_config" 'keybind = super+digit_1=text:\x1b1'
  assert_line "$ghostty_config" 'keybind = super+digit_2=text:\x1b2'
  assert_line "$ghostty_config" 'keybind = super+digit_3=text:\x1b3'
  assert_line "$ghostty_config" 'keybind = super+digit_4=text:\x1b4'
  assert_line "$ghostty_config" 'keybind = super+digit_5=text:\x1b5'
  assert_line "$ghostty_config" 'keybind = super+digit_6=text:\x1b6'
  assert_line "$ghostty_config" 'keybind = super+digit_7=text:\x1b7'
  assert_line "$ghostty_config" 'keybind = super+digit_8=text:\x1b8'
  assert_line "$ghostty_config" 'keybind = super+digit_9=text:\x1b9'
  assert_line "$ghostty_config" 'keybind = super+digit_0=text:\x1b0'
}

verify_ghostty
verify_karabiner_lint
verify_karabiner_terminal_invariants
verify_tmux

echo "terminal workflow verified"
