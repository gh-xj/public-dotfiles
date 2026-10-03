#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
target_user="${USER:-$(id -un)}"
target_home="${HOME:-/Users/$target_user}"
bootstrap_root="${XJ_PUBLIC_DOTFILES_BOOTSTRAP_DIR:-}"
profile_name="bootstrap"
home_state_version="25.11"
mode=""
show_plan=0
plan_json=0
host_platform=""
activation_generation=""
backup_extension="public-dotfiles-backup-$(date +%Y%m%d%H%M%S)"
package_sets=("shell" "dev" "ops")

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap-macos.sh {--plan [--json] | --apply | --rollback}

Build, apply, or roll back the standalone Home Manager profile. Apply runs
without sudo and includes the declared macOS user settings. Apps are separate.
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
      --plan) [ -z "$mode" ] || die "choose one operation"; show_plan=1; mode="plan" ;;
      --json) plan_json=1 ;;
      --apply) [ -z "$mode" ] || die "choose one operation"; mode="apply" ;;
      --rollback) [ -z "$mode" ] || die "choose one operation"; mode="rollback" ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option: $1" ;;
    esac
    shift
  done

  [ -n "$mode" ] || die "choose --plan, --apply, or --rollback"
  if [ "$plan_json" -eq 1 ] && [ "$show_plan" -eq 0 ]; then
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
  have_cmd git || die "missing required command: git"
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
  have_cmd nix || die "Nix is required; install Determinate Nix first"
  info "nix: $(nix --version)"
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
  activation_generation="$(nix_cmd build --no-link --print-out-paths \
    "$flake_dir#homeConfigurations.$profile_name.activationPackage")"
}

rollback_home_manager() {
  local profile="${XDG_STATE_HOME:-$target_home/.local/state}/nix/profiles/home-manager"
  [ -e "$profile" ] || die "Home Manager profile does not exist"
  nix-env --profile "$profile" --rollback
  "$(readlink -f "$profile")/activate"
}

apply_home_manager() {
  local flake_dir="$1"
  [ "$mode" = apply ] || return 0
  info "running standalone Home Manager switch"
  nix_cmd run "$flake_dir#home-manager" -- switch \
    --flake "$flake_dir#$profile_name" -b "$backup_extension"
}

main() {
  local flake_dir
  parse_args "$@"
  if [ -z "$bootstrap_root" ]; then
    if [ "$mode" = plan ]; then
      bootstrap_root="$(mktemp -d)"
      trap 'rm -rf -- "$bootstrap_root"' EXIT
    else
      bootstrap_root="${XDG_STATE_HOME:-$target_home/.local/state}/public-dotfiles/bootstrap"
    fi
  fi
  guard_private_overlay_apply
  preflight
  ensure_nix
  if [ "$mode" = rollback ]; then
    rollback_home_manager
    return
  fi
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

  apply_home_manager "$flake_dir"
  info "Home Manager and macOS settings apply complete; next run: task apps"
}

main "$@"
