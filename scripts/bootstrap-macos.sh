#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
initial_user="${USER:-$(id -un)}"
initial_home="${HOME:-/Users/$initial_user}"
bootstrap_root="${XJ_PUBLIC_DOTFILES_BOOTSTRAP_DIR:-${XDG_STATE_HOME:-$initial_home/.local/state}/public-dotfiles/bootstrap}"
profile_name="bootstrap"
target_user="$initial_user"
target_home="$initial_home"
home_state_version="25.11"
mode="dry-run"
darwin_phase=0
nix_install_mode="never"
homebrew_prefix="/opt/homebrew"
homebrew_install_mode="auto"
package_sets=("shell" "dev" "ops")
hm_extra_args=()
hm_extra_arg_count=0

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap-macos.sh [options] [-- home-manager args...]

Stock-macOS entrypoint for the public dotfiles baseline.

Default behavior is a non-mutating preflight. It generates a machine-local
flake under the user state directory and builds the Home Manager activation
package when nix is already available. Use --apply to run home-manager switch.
Use --darwin --apply for the sudo-backed nix-darwin system phase that manages
the public Homebrew GUI/app ledger.

Options:
  --dry-run                    Preflight and build only when nix exists (default)
  --apply                      Run home-manager switch after preflight
  --darwin                     Also build/apply the generated nix-darwin system host
  --install-nix[=official]     Install upstream Nix with the official macOS daemon installer if nix is missing
  --install-nix=determinate    Install Determinate Nix with its CLI installer if nix is missing
  --no-install-homebrew        With --darwin --apply, fail instead of installing missing Homebrew
  --homebrew-prefix PATH       Homebrew prefix for nix-darwin (default: /opt/homebrew)
  --user NAME                  macOS user for Home Manager (default: current user)
  --home PATH                  Home directory for that user (default: current HOME)
  --state-version VERSION      Home Manager stateVersion (default: 25.11)
  --package-sets LIST          Comma-separated package sets (default: shell,dev,ops)
  -h, --help                   Show this help

Examples:
  scripts/bootstrap-macos.sh
  scripts/bootstrap-macos.sh --apply
  scripts/bootstrap-macos.sh --darwin
  scripts/bootstrap-macos.sh --darwin --apply
  scripts/bootstrap-macos.sh --install-nix --apply
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

require_cmd() {
  have_cmd "$1" || die "missing required command: $1"
}

csv_to_array() {
  local csv="$1"
  local old_ifs="$IFS"
  IFS=,
  # shellcheck disable=SC2206
  package_sets=($csv)
  IFS="$old_ifs"
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
      --dry-run)
        mode="dry-run"
        ;;
      --apply)
        mode="apply"
        ;;
      --darwin)
        darwin_phase=1
        ;;
      --install-nix)
        nix_install_mode="official"
        ;;
      --install-nix=official)
        nix_install_mode="official"
        ;;
      --install-nix=determinate)
        nix_install_mode="determinate"
        ;;
      --no-install-homebrew)
        homebrew_install_mode="never"
        ;;
      --homebrew-prefix)
        shift
        [ "$#" -gt 0 ] || die "--homebrew-prefix requires a value"
        homebrew_prefix="$1"
        ;;
      --homebrew-prefix=*)
        homebrew_prefix="${1#--homebrew-prefix=}"
        ;;
      --user)
        shift
        [ "$#" -gt 0 ] || die "--user requires a value"
        target_user="$1"
        ;;
      --user=*)
        target_user="${1#--user=}"
        ;;
      --home)
        shift
        [ "$#" -gt 0 ] || die "--home requires a value"
        target_home="$1"
        ;;
      --home=*)
        target_home="${1#--home=}"
        ;;
      --state-version)
        shift
        [ "$#" -gt 0 ] || die "--state-version requires a value"
        home_state_version="$1"
        ;;
      --state-version=*)
        home_state_version="${1#--state-version=}"
        ;;
      --package-sets)
        shift
        [ "$#" -gt 0 ] || die "--package-sets requires a value"
        csv_to_array "$1"
        ;;
      --package-sets=*)
        csv_to_array "${1#--package-sets=}"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        hm_extra_arg_count="$#"
        hm_extra_args=("$@")
        break
        ;;
      *)
        die "unknown option: $1"
        ;;
    esac
    shift
  done
}

preflight() {
  local uname_s uname_m
  uname_s="$(uname -s)"
  uname_m="$(uname -m)"

  [ "$uname_s" = "Darwin" ] || die "this bootstrap currently supports macOS only; found $uname_s"
  [ "$uname_m" = "arm64" ] || die "this flake currently exports aarch64-darwin only; found $uname_m"

  require_cmd git
  require_cmd curl
  require_cmd zsh

  [ -n "$target_user" ] || die "target user is empty"
  [ -n "$target_home" ] || die "target home is empty"
  [ -n "$homebrew_prefix" ] || die "homebrew prefix is empty"
  [ "${#package_sets[@]}" -gt 0 ] || die "at least one package set is required"

  info "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  info "arch: $uname_m"
  info "repo: $repo_root"
  info "target Home Manager user: $target_user"
  info "target home: $target_home"
  info "package sets: ${package_sets[*]}"
  if [ "$darwin_phase" -eq 1 ]; then
    info "Darwin system phase: enabled"
    info "Homebrew prefix: $homebrew_prefix"
  fi
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

install_nix_if_requested() {
  load_nix_profile

  if have_cmd nix; then
    info "nix: $(nix --version)"
    return
  fi

  if [ "$nix_install_mode" = "never" ]; then
    info "nix is missing; skipping install in dry preflight"
    cat <<'EOF'

Install options:
  official macOS daemon installer:
    bash <(curl -L https://nixos.org/nix/install) --daemon

  Determinate CLI installer:
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

Then open a new shell or rerun this script with --install-nix.
EOF
    return
  fi

  case "$nix_install_mode" in
    official)
      info "installing Nix with the official macOS daemon installer"
      bash <(curl -L https://nixos.org/nix/install) --daemon
      ;;
    determinate)
      info "installing Determinate Nix with its CLI installer"
      curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
      ;;
    *)
      die "unsupported nix install mode: $nix_install_mode"
      ;;
  esac

  load_nix_profile
  have_cmd nix || die "nix was installed, but this shell cannot find it yet; open a new shell and rerun"
  info "nix: $(nix --version)"
}

write_bootstrap_flake() {
  local flake_dir="$bootstrap_root/$target_user"
  local flake_file="$flake_dir/flake.nix"
  local darwin_inputs=""
  local darwin_package=""
  local darwin_configuration=""
  local outputs_args="inputs@{ public, nixpkgs, home-manager, ... }"

  mkdir -p "$flake_dir"

  if [ "$darwin_phase" -eq 1 ]; then
    outputs_args="inputs@{ public, nixpkgs, home-manager, nix-darwin, ... }"
    darwin_inputs='    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";'
    darwin_package='    packages.aarch64-darwin.darwin-rebuild = nix-darwin.packages.aarch64-darwin.darwin-rebuild;'
    darwin_configuration=$(cat <<EOF
    darwinConfigurations.$profile_name = nix-darwin.lib.darwinSystem {
      specialArgs = {
        inherit inputs;
        self = public;
      };
      modules = [
        public.darwinModules.default
        ({ lib, ... }: {
          xj.publicDotfiles.darwin.enable = true;

          system = {
            primaryUser = $(nix_string "$target_user");
            stateVersion = 6;
          };

          users.users.$(nix_string "$target_user").home = $(nix_string "$target_home");
          nixpkgs.hostPlatform = "aarch64-darwin";

          # Bootstrap owns app/system convergence, not the Nix daemon itself.
          nix.enable = false;

          # Newer macOS releases already ship sudo_local.
          environment.etc."pam.d/sudo_local".enable = lib.mkForce false;

          homebrew.prefix = lib.mkDefault $(nix_string "$homebrew_prefix");
        })
      ];
    };
EOF
)
  fi

  cat > "$flake_file" <<EOF
{
  description = "Machine-local public-dotfiles bootstrap host";

  inputs = {
    public.url = $(nix_string "path:$repo_root");
    nixpkgs.follows = "public/nixpkgs";
    home-manager.follows = "public/home-manager";
$darwin_inputs
  };

  outputs = $outputs_args:
  {
    packages.aarch64-darwin.home-manager = home-manager.packages.aarch64-darwin.home-manager;
$darwin_package

    homeConfigurations.$profile_name = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.aarch64-darwin;
      extraSpecialArgs = {
        inherit inputs;
        self = public;
      };
      modules = [
        public.homeModules.default
        ({ ... }: {
          xj.publicDotfiles = {
            enable = true;
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

$darwin_configuration
  };
}
EOF

  rm -f "$flake_dir/flake.lock"

  info "generated local bootstrap flake: $flake_file"
  printf '%s\n' "$flake_dir"
}

build_activation() {
  local flake_dir="$1"

  if ! have_cmd nix; then
    info "skipping Home Manager build because nix is not installed"
    return
  fi

  info "building Home Manager activation package"
  nix_cmd build --no-link "$flake_dir#homeConfigurations.$profile_name.activationPackage"
}

build_darwin_system() {
  local flake_dir="$1"

  [ "$darwin_phase" -eq 1 ] || return 0

  if ! have_cmd nix; then
    info "skipping nix-darwin build because nix is not installed"
    return
  fi

  info "building nix-darwin system"
  nix_cmd build --no-link "$flake_dir#darwinConfigurations.$profile_name.system"
}

homebrew_command() {
  cat <<'EOF'
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
EOF
}

install_homebrew() {
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

homebrew_version() {
  local version
  version="$("$homebrew_prefix/bin/brew" --version)"
  printf '%s\n' "${version%%$'\n'*}"
}

ensure_homebrew_for_darwin() {
  [ "$darwin_phase" -eq 1 ] || return 0

  if [ -x "$homebrew_prefix/bin/brew" ]; then
    info "homebrew: $(homebrew_version)"
    return
  fi

  if [ "$mode" != "apply" ]; then
    info "Homebrew is missing at $homebrew_prefix/bin/brew"
    printf '\nInstall command used by --darwin --apply when Homebrew is missing:\n  %s\n\n' "$(homebrew_command)"
    return
  fi

  if [ "$homebrew_install_mode" = "never" ]; then
    die "Homebrew is missing at $homebrew_prefix/bin/brew; install it first or omit --no-install-homebrew"
  fi

  info "installing Homebrew with the official installer"
  install_homebrew

  [ -x "$homebrew_prefix/bin/brew" ] || die "Homebrew installer completed, but $homebrew_prefix/bin/brew is still missing"
  info "homebrew: $(homebrew_version)"
}

apply_home_manager() {
  local flake_dir="$1"

  [ "$mode" = "apply" ] || {
    return 0
  }

  have_cmd nix || die "--apply requires nix; rerun with --install-nix --apply or install nix first"

  info "running Home Manager switch"
  if [ "$hm_extra_arg_count" -gt 0 ]; then
    nix_cmd run "$flake_dir#home-manager" -- switch --flake "$flake_dir#$profile_name" "${hm_extra_args[@]}"
  else
    nix_cmd run "$flake_dir#home-manager" -- switch --flake "$flake_dir#$profile_name"
  fi
}

apply_darwin_system() {
  local flake_dir="$1"
  local darwin_rebuild

  [ "$darwin_phase" -eq 1 ] || return 0
  [ "$mode" = "apply" ] || return 0

  have_cmd nix || die "--darwin --apply requires nix; rerun with --install-nix --darwin --apply or install nix first"

  darwin_rebuild="$(nix_cmd build --no-link --print-out-paths "$flake_dir#darwin-rebuild")/bin/darwin-rebuild"
  info "running nix-darwin switch with sudo"
  sudo "$darwin_rebuild" switch --flake "$flake_dir#$profile_name"
}

finish_message() {
  [ "$mode" = "dry-run" ] || return 0

  if [ "$darwin_phase" -eq 1 ]; then
    info "dry run complete; rerun with --darwin --apply for Home Manager plus nix-darwin/Homebrew"
  else
    info "dry run complete; rerun with --apply to switch this user"
  fi
}

main() {
  local flake_dir

  parse_args "$@"
  cd "$repo_root"
  preflight
  install_nix_if_requested
  flake_dir="$(write_bootstrap_flake)"
  build_activation "$flake_dir"
  build_darwin_system "$flake_dir"
  ensure_homebrew_for_darwin
  apply_home_manager "$flake_dir"
  apply_darwin_system "$flake_dir"
  finish_message
}

main "$@"
