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
nix_install_version="${XJ_PUBLIC_DOTFILES_NIX_VERSION:-auto}"
host_platform=""
homebrew_prefix=""
macos_major=""
homebrew_install_mode="auto"
backup_extension="${XJ_PUBLIC_DOTFILES_BACKUP_EXTENSION:-public-dotfiles-backup-$(date +%Y%m%d%H%M%S)}"
migrate_nix_darwin_etc=1
display_layout_mode="auto"
skip_build=0
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
  --nix-version VERSION        Pin the official Nix installer version (default: auto)
  --no-install-homebrew        With --darwin --apply, fail instead of installing missing Homebrew
  --host-platform SYSTEM       Override detected Nix Darwin system for dry-run testing
                               (aarch64-darwin or x86_64-darwin)
  --homebrew-prefix PATH       Homebrew prefix for nix-darwin
                               (default: /opt/homebrew on Apple Silicon, /usr/local on Intel)
  --backup-extension EXT       Backup unmanaged files before linking Home Manager paths
                               (default: public-dotfiles-backup-<timestamp>)
  --no-backup                  Fail instead of backing up unmanaged Home Manager link targets
  --no-migrate-nix-darwin-etc  Fail instead of backing up first-run /etc shell rc files
  --no-display-layout          Skip displayplacer layout policy after nix-darwin apply
  --skip-build                 Generate and inspect bootstrap config without Nix builds
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

enable_nix_flake_features() {
  local features_config="experimental-features = nix-command flakes"

  case "${NIX_CONFIG:-}" in
    *nix-command*flakes*|*flakes*nix-command*)
      return
      ;;
    "")
      export NIX_CONFIG="$features_config"
      ;;
    *)
      export NIX_CONFIG="${NIX_CONFIG}"$'\n'"$features_config"
      ;;
  esac
}

require_cmd() {
  have_cmd "$1" || die "missing required command: $1"
}

darwin_system_from_uname() {
  case "$1" in
    arm64)
      printf '%s\n' "aarch64-darwin"
      ;;
    x86_64)
      printf '%s\n' "x86_64-darwin"
      ;;
    *)
      die "this bootstrap supports arm64 and x86_64 macOS only; found $1"
      ;;
  esac
}

default_homebrew_prefix_for_system() {
  case "$1" in
    aarch64-darwin)
      printf '%s\n' "/opt/homebrew"
      ;;
    x86_64-darwin)
      printf '%s\n' "/usr/local"
      ;;
    *)
      die "unsupported Darwin host platform: $1"
      ;;
  esac
}

validate_host_platform() {
  case "$1" in
    aarch64-darwin|x86_64-darwin)
      ;;
    *)
      die "unsupported --host-platform: $1"
      ;;
  esac
}

macos_major_version() {
  if [ -n "${XJ_PUBLIC_DOTFILES_MACOS_MAJOR_OVERRIDE:-}" ]; then
    printf '%s\n' "$XJ_PUBLIC_DOTFILES_MACOS_MAJOR_OVERRIDE"
    return
  fi

  sw_vers -productVersion | awk -F. '{ print $1 }'
}

resolve_nix_install_version() {
  local major

  [ "$nix_install_version" = "auto" ] || return 0

  major="${macos_major:-$(macos_major_version)}"
  if [ "$host_platform" = "x86_64-darwin" ] && [ "$major" -lt 14 ]; then
    # Current upstream x86_64-darwin Nix binaries require macOS 14+.
    nix_install_version="2.29.4"
  else
    nix_install_version="latest"
  fi
}

official_nix_install_url() {
  if [ "$nix_install_version" = "latest" ]; then
    printf '%s\n' "https://nixos.org/nix/install"
  else
    printf 'https://releases.nixos.org/nix/nix-%s/install\n' "$nix_install_version"
  fi
}

guard_partial_nix_install() {
  [ "$nix_install_mode" != "never" ] || return 0
  [ -d /nix/store ] || return 0
  [ ! -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ] || return 0

  cat >&2 <<'EOF'
bootstrap: detected a partial Nix install at /nix/store, but no usable Nix profile.
bootstrap: clean the failed macOS Nix volume/launchd/fstab/synthetic.conf state before retrying.
bootstrap: see docs/bootstrap.md "Recover A Failed macOS Nix Install".
EOF
  exit 1
}

require_sudo_for_darwin_apply() {
  [ "$darwin_phase" -eq 1 ] || return 0
  [ "$mode" = "apply" ] || return 0

  if sudo -n true >/dev/null 2>&1; then
    return 0
  fi

  if [ -t 0 ]; then
    info "requesting sudo credentials for nix-darwin apply"
    sudo -v || die "--darwin --apply requires sudo"
    return 0
  fi

  die "--darwin --apply requires sudo credentials; rerun from an interactive terminal/SSH session or pre-authorize sudo on the target machine"
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
      --nix-version)
        shift
        [ "$#" -gt 0 ] || die "--nix-version requires a value"
        nix_install_version="$1"
        ;;
      --nix-version=*)
        nix_install_version="${1#--nix-version=}"
        ;;
      --no-install-homebrew)
        homebrew_install_mode="never"
        ;;
      --host-platform)
        shift
        [ "$#" -gt 0 ] || die "--host-platform requires a value"
        host_platform="$1"
        ;;
      --host-platform=*)
        host_platform="${1#--host-platform=}"
        ;;
      --homebrew-prefix)
        shift
        [ "$#" -gt 0 ] || die "--homebrew-prefix requires a value"
        homebrew_prefix="$1"
        ;;
      --homebrew-prefix=*)
        homebrew_prefix="${1#--homebrew-prefix=}"
        ;;
      --backup-extension)
        shift
        [ "$#" -gt 0 ] || die "--backup-extension requires a value"
        [ -n "$1" ] || die "--backup-extension cannot be empty"
        backup_extension="$1"
        ;;
      --backup-extension=*)
        backup_extension="${1#--backup-extension=}"
        [ -n "$backup_extension" ] || die "--backup-extension cannot be empty"
        ;;
      --no-backup)
        backup_extension=""
        ;;
      --no-migrate-nix-darwin-etc)
        migrate_nix_darwin_etc=0
        ;;
      --no-display-layout)
        display_layout_mode="skip"
        ;;
      --skip-build)
        skip_build=1
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
  local detected_platform uname_s uname_m
  uname_s="$(uname -s)"
  uname_m="$(uname -m)"

  [ "$uname_s" = "Darwin" ] || die "this bootstrap currently supports macOS only; found $uname_s"
  detected_platform="$(darwin_system_from_uname "$uname_m")"
  if [ -z "$host_platform" ]; then
    host_platform="$detected_platform"
  else
    validate_host_platform "$host_platform"
    if [ "$host_platform" != "$detected_platform" ] && [ "$mode" != "dry-run" ]; then
      die "--host-platform can only differ from the detected platform in dry-run mode"
    fi
  fi
  if [ -z "$homebrew_prefix" ]; then
    homebrew_prefix="$(default_homebrew_prefix_for_system "$host_platform")"
  fi
  macos_major="$(macos_major_version)"
  case "$macos_major" in
    ""|*[!0-9]*)
      die "invalid macOS major version: $macos_major"
      ;;
  esac
  resolve_nix_install_version

  require_cmd git
  require_cmd curl
  require_cmd zsh

  [ -n "$target_user" ] || die "target user is empty"
  [ -n "$target_home" ] || die "target home is empty"
  [ -n "$homebrew_prefix" ] || die "homebrew prefix is empty"
  [ "${#package_sets[@]}" -gt 0 ] || die "at least one package set is required"

  info "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  info "detected arch: $uname_m"
  info "Nix host platform: $host_platform"
  info "Nix installer version: $nix_install_version"
  info "repo: $repo_root"
  info "target Home Manager user: $target_user"
  info "target home: $target_home"
  info "package sets: ${package_sets[*]}"
  if [ "$mode" = "apply" ]; then
    if [ -n "$backup_extension" ]; then
      info "Home Manager conflict backups: *.$backup_extension"
    else
      info "Home Manager conflict backups: disabled"
    fi
  fi
  if [ "$darwin_phase" -eq 1 ]; then
    info "Darwin system phase: enabled"
    info "Darwin Homebrew macOS major: $macos_major"
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
    cat <<EOF

Install options:
  official macOS daemon installer:
    bash <(curl -L $(official_nix_install_url)) --daemon

  Determinate CLI installer:
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

Then open a new shell or rerun this script with --install-nix.
EOF
    return
  fi

  guard_partial_nix_install

  case "$nix_install_mode" in
    official)
      info "installing Nix with the official macOS daemon installer from $(official_nix_install_url)"
      bash <(curl -L "$(official_nix_install_url)") --daemon
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
    darwin_package="    packages.$host_platform.darwin-rebuild = nix-darwin.packages.$host_platform.darwin-rebuild;"
    darwin_configuration=$(cat <<EOF
    darwinConfigurations.$profile_name = nix-darwin.lib.darwinSystem {
      specialArgs = {
        inherit inputs;
        self = public;
      };
      modules = [
        public.darwinModules.default
        ({ lib, ... }: {
          xj.publicDotfiles.darwin = {
            enable = true;
            macosMajor = $macos_major;
          };

          system = {
            primaryUser = $(nix_string "$target_user");
            stateVersion = 6;
          };

          users.users.$(nix_string "$target_user").home = $(nix_string "$target_home");
          nixpkgs.hostPlatform = $(nix_string "$host_platform");

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
  let
    pkgs = import nixpkgs {
      system = $(nix_string "$host_platform");
      config.allowUnfreePredicate = pkg:
        builtins.elem (nixpkgs.lib.getName pkg) [
          "claude-code"
        ];
    };
  in
  {
    packages.$host_platform.home-manager = home-manager.packages.$host_platform.home-manager;
$darwin_package

    homeConfigurations.$profile_name = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs;
        self = public;
      };
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
  if [ "$skip_build" -eq 1 ]; then
    info "skipping Home Manager build because --skip-build was requested"
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
  if [ "$skip_build" -eq 1 ]; then
    info "skipping nix-darwin build because --skip-build was requested"
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

prepare_nix_darwin_etc() {
  local file backup target

  [ "$darwin_phase" -eq 1 ] || return 0
  [ "$mode" = "apply" ] || return 0
  [ "$migrate_nix_darwin_etc" -eq 1 ] || return 0

  for file in /etc/bashrc /etc/zshrc; do
    [ -e "$file" ] || [ -L "$file" ] || continue

    target="$(readlink "$file" 2>/dev/null || true)"
    case "$target" in
      /etc/static/*)
        continue
        ;;
    esac

    backup="$file.before-nix-darwin"
    if [ -e "$backup" ] || [ -L "$backup" ]; then
      die "$file blocks nix-darwin activation, but $backup already exists; inspect those files and move one manually"
    fi

    info "backing up $file to $backup for nix-darwin ownership"
    sudo mv "$file" "$backup"
  done
}

hm_args_include_backup_extension() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      -b|--backup-extension|--backup-extension=*)
        return 0
        ;;
    esac
  done
  return 1
}

apply_home_manager() {
  local flake_dir="$1"
  local hm_args_have_backup=0
  local switch_args

  [ "$mode" = "apply" ] || {
    return 0
  }

  have_cmd nix || die "--apply requires nix; rerun with --install-nix --apply or install nix first"

  switch_args=(switch --flake "$flake_dir#$profile_name")
  if [ "$hm_extra_arg_count" -gt 0 ] && hm_args_include_backup_extension "${hm_extra_args[@]}"; then
    hm_args_have_backup=1
  fi
  if [ -n "$backup_extension" ] && [ "$hm_args_have_backup" -eq 0 ]; then
    switch_args+=(-b "$backup_extension")
  fi
  if [ "$hm_extra_arg_count" -gt 0 ]; then
    switch_args+=("${hm_extra_args[@]}")
  fi

  info "running Home Manager switch"
  nix_cmd run "$flake_dir#home-manager" -- "${switch_args[@]}"
}

install_public_npm_globals() {
  [ "$mode" = "apply" ] || return 0

  if [ -f "$repo_root/npm-globals.txt" ]; then
    info "installing public npm globals"
    HOME="$target_home" XDG_DATA_HOME="${XDG_DATA_HOME:-$target_home/.local/share}" "$repo_root/scripts/install-npm-globals.sh"
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

apply_display_layout() {
  [ "$darwin_phase" -eq 1 ] || return 0
  [ "$mode" = "apply" ] || return 0
  [ "$display_layout_mode" = "auto" ] || return 0

  info "applying display layout policy"
  "$repo_root/scripts/apply-display-layout.sh" --apply
}

apply_current_host_defaults() {
  [ "$darwin_phase" -eq 1 ] || return 0
  [ "$mode" = "apply" ] || return 0

  info "applying currentHost input defaults"
  "$repo_root/scripts/apply-current-host-defaults.sh" --apply --allow-live-mismatch
}

finish_message() {
  if [ "$mode" = "dry-run" ]; then
    if [ "$darwin_phase" -eq 1 ]; then
      info "dry run complete; rerun with --darwin --apply for Home Manager plus nix-darwin/Homebrew"
    else
      info "dry run complete; rerun with --apply to switch this user"
    fi
    return 0
  fi

  if [ "$darwin_phase" -eq 1 ]; then
    info "apply complete; run: task dotfiles:verify"
  else
    info "Home Manager apply complete; run: task dotfiles:verify-user"
    info "rerun with --darwin --apply for the Homebrew GUI/app ledger and full verification"
  fi
}

main() {
  local flake_dir

  parse_args "$@"
  enable_nix_flake_features
  cd "$repo_root"
  preflight
  require_sudo_for_darwin_apply
  install_nix_if_requested
  prepare_nix_darwin_etc
  flake_dir="$(write_bootstrap_flake)"
  build_activation "$flake_dir"
  build_darwin_system "$flake_dir"
  ensure_homebrew_for_darwin
  apply_home_manager "$flake_dir"
  install_public_npm_globals
  apply_darwin_system "$flake_dir"
  apply_current_host_defaults
  apply_display_layout
  finish_message
}

main "$@"
