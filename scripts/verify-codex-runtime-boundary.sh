#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

live=0
home_dir="${HOME:-}"

usage() {
  cat <<'USAGE'
Usage: verify-codex-runtime-boundary.sh [--live] [--home HOME]

Verifies that public-dotfiles keeps Codex baseline settings public-safe without
owning the mutable live Codex runtime config.

--live       Also verify the live HOME/.codex/config.toml is writable.
--home HOME  HOME directory to use with --live.
USAGE
}

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --live)
      live=1
      shift
      ;;
    --home)
      [ "$#" -ge 2 ] || fail "--home requires a value"
      home_dir="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "unknown argument: $1"
      ;;
  esac
done

nix_cmd() {
  nix --extra-experimental-features "nix-command flakes" "$@"
}

template=".codex/config.toml"
[ -f "$template" ] || fail "missing public Codex template: $template"

if grep -En '^[[:space:]]*(\[projects\.|\[(marketplaces|plugins|model_providers)(\.|\])|trust_level[[:space:]]*=|.*(api_key|auth_token|access_token|refresh_token|client_secret|password)[[:space:]]*=)' "$template" >&2; then
  fail "$template contains runtime, provider, trust, or secret-like state"
fi

if grep -En '(/Users/xj/|/Volumes/|private-config|xj-private-brain)' "$template" >&2; then
  fail "$template contains machine-local or private path state"
fi

activation_attr="$("$repo_root/scripts/home-config-attr.sh" activation-package)"
generation="$(nix_cmd build --no-link --print-out-paths "$activation_attr")"
home_files="$(readlink "$generation/home-files")"

for path in ".codex/AGENTS.md" ".codex/rules/default.rules"; do
  if [ ! -e "$home_files/$path" ] && [ ! -L "$home_files/$path" ]; then
    fail "missing generated public Codex policy file: $path"
  fi
done

if [ -e "$home_files/.codex/config.toml" ] || [ -L "$home_files/.codex/config.toml" ]; then
  fail "Home Manager must not own .codex/config.toml; it is mutable Codex runtime state"
fi

if [ "$live" -eq 1 ]; then
  [ -n "$home_dir" ] || fail "HOME is not set; pass --home"
  live_config="$home_dir/.codex/config.toml"

  if [ ! -e "$live_config" ]; then
    fail "missing live Codex config: $live_config"
  fi

  if [ -L "$live_config" ]; then
    link_target="$(readlink "$live_config" 2>/dev/null || true)"
    case "$link_target" in
      /nix/store/*)
        fail "$live_config points into /nix/store; Codex cannot persist project trust"
        ;;
    esac
  fi

  if [ ! -w "$live_config" ]; then
    fail "$live_config is not writable; Codex project trust prompts may fail"
  fi
fi

echo "Codex runtime boundary verified"
