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

template="config/codex/config.toml"
[ -f "$template" ] || fail "missing public Codex template: $template"
hooks="config/codex/hooks.json"
[ -f "$hooks" ] || fail "missing public Codex hooks: $hooks"
jq empty "$hooks" || fail "$hooks is not valid JSON"
if grep -Eq '^[[:space:]]*codex_hooks[[:space:]]*=' "$template"; then
  fail "deprecated hook feature key; use features.hooks"
fi
if grep -Eq '^\[notice([.]|\])|^[[:space:]]*windows_wsl_setup_acknowledged[[:space:]]*=' "$template"; then
  fail "runtime notice/onboarding state must not be seeded"
fi
python3 scripts/verify-codex-strict.py

if grep -R -En 'pkgs\.codex|@openai/codex' packages npm-globals.txt 2>/dev/null >&2; then
  fail "Codex CLI must use the official standalone installer, not Nix or npm"
fi

if grep -En '(/Users/|/Volumes/)' "$hooks" >&2; then
  fail "$hooks contains machine-local or private path state"
fi

if [ -e ".codex/config.toml" ] || [ -L ".codex/config.toml" ]; then
  fail ".codex/config.toml is a reserved project-local Codex path; keep the public seed template at $template"
fi

if grep -En '^[[:space:]]*(\[projects\.|\[(marketplaces|plugins|model_providers)(\.|\])|trust_level[[:space:]]*=|.*(api_key|auth_token|access_token|refresh_token|client_secret|password)[[:space:]]*=)' "$template" >&2; then
  fail "$template contains runtime, provider, trust, or secret-like state"
fi

if grep -En '(/Users/|/Volumes/)' "$template" >&2; then
  fail "$template contains machine-local or private path state"
fi

activation_attr="$("$repo_root/scripts/home-config-attr.sh" activation-package)"
generation="$(nix_cmd build --no-link --print-out-paths "$activation_attr")"
home_files="$(readlink "$generation/home-files")"

for path in ".codex/AGENTS.md" ".codex/hooks.json" ".codex/rules/default.rules"; do
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
  standalone_link="$home_dir/.local/bin/codex"

  if [ ! -L "$standalone_link" ]; then
    fail "missing standalone Codex CLI link: $standalone_link"
  fi

  standalone_target="$(readlink "$standalone_link" 2>/dev/null || true)"
  case "$standalone_target" in
    "$home_dir/.codex/packages/standalone/"*/bin/codex) ;;
    *) fail "$standalone_link does not point to the official standalone package: $standalone_target" ;;
  esac

  resolved_codex="$(command -v codex 2>/dev/null || true)"
  if [ "$resolved_codex" != "$standalone_link" ]; then
    fail "codex resolves to $resolved_codex instead of $standalone_link; remove duplicate CLI installs"
  fi

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
    resolved_config="$(realpath "$live_config")"
    config_repo="$(git -C "$(dirname "$resolved_config")" rev-parse --show-toplevel 2>/dev/null || true)"
    [ -z "$config_repo" ] || fail "live Codex config resolves into a Git repository"
  fi

  if grep -Eq '^[[:space:]]*codex_hooks[[:space:]]*=' "$live_config"; then
    fail "live config uses deprecated hook feature key; use features.hooks"
  fi

  if [ ! -w "$live_config" ]; then
    fail "$live_config is not writable; Codex project trust prompts may fail"
  fi
fi

echo "Codex runtime boundary verified"
