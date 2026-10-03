#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
target_user="${USER:-$(id -un)}"
target_home="${HOME:-/Users/$target_user}"
bootstrap_root="${XJ_PUBLIC_DOTFILES_BOOTSTRAP_DIR:-${XDG_STATE_HOME:-$target_home/.local/state}/public-dotfiles/bootstrap}"
profile_name="bootstrap"
home_state_version="25.11"
mode="dry-run"
show_plan=0
plan_json=0
skip_build=0
host_platform=""
homebrew_prefix=""
activation_generation=""
backup_extension="public-dotfiles-backup-$(date +%Y%m%d%H%M%S)"
package_sets=("shell" "dev" "ops")

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap-macos.sh [--dry-run|--plan [--json]|--apply] [--skip-build]

Build or apply the standalone Home Manager profile. Apply mode installs
Determinate Nix and Homebrew when missing; it never manages system settings.
After apply, run `task apps` and `mise install --locked`.
EOF
}

die() {
  printf 'bootstrap: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '==> %s\n' "$*" >&2
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

nix_cmd() {
  nix --extra-experimental-features "nix-command flakes" "$@"
}

nix_string() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

nix_list_strings() {
  local item
  for item in "$@"; do
    printf '%s ' "$(nix_string "$item")"
  done
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --plan) show_plan=1 ;;
      --json) plan_json=1 ;;
      --dry-run) mode="dry-run" ;;
      --apply) mode="apply" ;;
      --skip-build) skip_build=1 ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option: $1" ;;
    esac
    shift
  done

  if [ "$show_plan" -eq 1 ]; then
    [ "$mode" != "apply" ] || die "--plan cannot be combined with --apply"
    [ "$skip_build" -eq 0 ] || die "--plan requires a built generation"
  elif [ "$plan_json" -eq 1 ]; then
    die "--json requires --plan"
  fi
}

host_system() {
  case "$(uname -m)" in
    arm64) printf '%s\n' aarch64-darwin ;;
    x86_64) printf '%s\n' x86_64-darwin ;;
    *) die "unsupported macOS architecture: $(uname -m)" ;;
  esac
}

preflight() {
  [ "$(uname -s)" = Darwin ] || die "this bootstrap supports macOS only"
  host_platform="$(host_system)"
  case "$host_platform" in
    aarch64-darwin) homebrew_prefix=/opt/homebrew ;;
    x86_64-darwin) homebrew_prefix=/usr/local ;;
  esac
  have_cmd git || die "missing required command: git"
  have_cmd curl || die "missing required command: curl"
  have_cmd zsh || die "missing required command: zsh"
  info "Home Manager target: $target_user at $target_home ($host_platform)"
}

guard_private_overlay_apply() {
  [ "$mode" = apply ] || return 0
  [ -f "$repo_root/../private-config/flake.nix" ] || return 0
  die "an adjacent private-config composes this user; apply from that repo instead"
}

load_nix_profile() {
  local profile
  for profile in \
    /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh \
    /nix/var/nix/profiles/default/etc/profile.d/nix.sh
  do
    if [ -r "$profile" ]; then
      # shellcheck source=/dev/null
      . "$profile"
    fi
  done
}

ensure_nix() {
  load_nix_profile
  if have_cmd nix; then
    info "nix: $(nix --version)"
    return 0
  fi
  if [ "$mode" != apply ]; then
    info "Nix is missing; apply mode would install Determinate Nix"
    return 0
  fi
  info "installing Determinate Nix"
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install
  load_nix_profile
  have_cmd nix || die "Nix installed but is not available; open a new shell and retry"
}

ensure_homebrew() {
  if [ -x "$homebrew_prefix/bin/brew" ]; then
    info "homebrew: $("$homebrew_prefix/bin/brew" --version | sed -n '1p')"
    return 0
  fi
  if [ "$mode" != apply ]; then
    info "Homebrew is missing; apply mode would install it"
    return 0
  fi
  info "installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  [ -x "$homebrew_prefix/bin/brew" ] || die "Homebrew installer did not create $homebrew_prefix/bin/brew"
}

write_bootstrap_flake() {
  local flake_dir="$bootstrap_root/$target_user"
  mkdir -p "$flake_dir"
  cat >"$flake_dir/flake.nix" <<EOF
{
  description = "Machine-local public-dotfiles Home Manager host";
  inputs = {
    public.url = $(nix_string "path:$repo_root");
    nixpkgs.follows = "public/nixpkgs";
    home-manager.follows = "public/home-manager";
  };
  outputs = inputs@{ public, nixpkgs, home-manager, ... }: {
    packages.$host_platform.home-manager = home-manager.packages.$host_platform.home-manager;
    homeConfigurations.$profile_name = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs { system = $(nix_string "$host_platform"); };
      extraSpecialArgs = { inherit inputs; self = public; };
      modules = [
        public.homeModules.default
        ({ ... }: {
          xj.publicDotfiles = {
            enable = true;
            repoRoot = $(nix_string "$repo_root");
            packageSets = [ $(nix_list_strings "${package_sets[@]}")];
          };
          home = {
            username = $(nix_string "$target_user");
            homeDirectory = $(nix_string "$target_home");
            stateVersion = $(nix_string "$home_state_version");
          };
          programs.home-manager.enable = true;
        })
      ];
    };
  };
}
EOF
  info "generated local Home Manager flake: $flake_dir/flake.nix"
  printf '%s\n' "$flake_dir"
}

build_activation() {
  local flake_dir="$1"
  if ! have_cmd nix; then
    info "skipping build because Nix is not installed"
    return 0
  fi
  [ "$skip_build" -eq 0 ] || { info "skipping build as requested"; return 0; }
  activation_generation="$(nix_cmd build --no-link --print-out-paths \
    "$flake_dir#homeConfigurations.$profile_name.activationPackage")"
}

apply_home_manager() {
  local flake_dir="$1"
  [ "$mode" = apply ] || return 0
  zsh "$repo_root/scripts/migrate-ghostty-parent.zsh" \
    --home "$target_home" --repo "$repo_root" --apply
  info "running standalone Home Manager switch"
  nix_cmd run "$flake_dir#home-manager" -- switch \
    --flake "$flake_dir#$profile_name" -b "$backup_extension"
}

main() {
  local flake_dir
  parse_args "$@"
  guard_private_overlay_apply
  preflight
  ensure_nix
  ensure_homebrew
  flake_dir="$(write_bootstrap_flake)"
  build_activation "$flake_dir"

  if [ "$show_plan" -eq 1 ]; then
    [ -n "$activation_generation" ] || die "--plan requires Nix"
    plan_args=(--generation "$activation_generation" --source-mode working-tree --scope home)
    [ "$plan_json" -eq 0 ] || plan_args+=(--json)
    python3 "$repo_root/scripts/public-control.py" --repo "$repo_root" \
      --home "$target_home" plan "${plan_args[@]}"
    return 0
  fi

  if [ "$mode" = apply ]; then
    apply_home_manager "$flake_dir"
    info "Home Manager apply complete; next run: task apps && mise install --locked"
  else
    info "dry run complete; use task apply to activate"
  fi
}

main "$@"
