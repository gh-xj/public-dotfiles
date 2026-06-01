#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

nix_cmd() {
  nix --extra-experimental-features "nix-command flakes" "$@"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$1" >&2
    exit 1
  }
}

generate_intel_darwin_flake() {
  local major="$1"

  env \
    XJ_PUBLIC_DOTFILES_BOOTSTRAP_DIR="$tmpdir/macos-$major" \
    XJ_PUBLIC_DOTFILES_MACOS_MAJOR_OVERRIDE="$major" \
    "$repo_root/scripts/bootstrap-macos.sh" \
      --darwin \
      --dry-run \
      --host-platform x86_64-darwin \
      --skip-build \
      --user example \
      --home /Users/example >/dev/null

  printf '%s\n' "$tmpdir/macos-$major/example"
}

eval_homebrew_json() {
  local flake_dir="$1"
  local attr="$2"

  nix_cmd eval --json "$flake_dir#darwinConfigurations.bootstrap.config.homebrew.$attr"
}

json_includes() {
  local json="$1"
  local item="$2"

  printf '%s' "$json" | ruby -rjson -e '
    item = ARGV.fetch(0)
    values = JSON.parse($stdin.read)
    found = values.any? do |value|
      value == item || (value.is_a?(Hash) && value["name"] == item)
    end
    exit(found ? 0 : 1)
  ' "$item"
}

assert_present() {
  local json="$1"
  local item="$2"
  local label="$3"

  if ! json_includes "$json" "$item"; then
    printf 'expected %s to include %s\n' "$label" "$item" >&2
    exit 1
  fi
}

assert_absent() {
  local json="$1"
  local item="$2"
  local label="$3"

  if json_includes "$json" "$item"; then
    printf 'expected %s to exclude %s\n' "$label" "$item" >&2
    exit 1
  fi
}

require_cmd nix
require_cmd ruby

flake_13="$(generate_intel_darwin_flake 13)"
casks_13="$(eval_homebrew_json "$flake_13" casks)"
taps_13="$(eval_homebrew_json "$flake_13" taps)"
assert_absent "$casks_13" "orbstack" "macOS 13 casks"
assert_absent "$casks_13" "chatgpt" "macOS 13 casks"
assert_absent "$casks_13" "typewhisper" "macOS 13 casks"
assert_absent "$taps_13" "typewhisper/tap" "macOS 13 taps"

flake_14="$(generate_intel_darwin_flake 14)"
casks_14="$(eval_homebrew_json "$flake_14" casks)"
taps_14="$(eval_homebrew_json "$flake_14" taps)"
assert_present "$casks_14" "orbstack" "macOS 14 casks"
assert_present "$casks_14" "chatgpt" "macOS 14 casks"
assert_absent "$casks_14" "typewhisper" "macOS 14 casks"
assert_absent "$taps_14" "typewhisper/tap" "macOS 14 taps"

flake_15="$(generate_intel_darwin_flake 15)"
casks_15="$(eval_homebrew_json "$flake_15" casks)"
taps_15="$(eval_homebrew_json "$flake_15" taps)"
assert_present "$casks_15" "orbstack" "macOS 15 casks"
assert_present "$casks_15" "chatgpt" "macOS 15 casks"
assert_present "$casks_15" "typewhisper" "macOS 15 casks"
assert_present "$taps_15" "typewhisper/tap" "macOS 15 taps"

echo "darwin Homebrew version gates verified"
