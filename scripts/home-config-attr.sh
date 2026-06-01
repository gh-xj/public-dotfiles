#!/usr/bin/env bash
set -euo pipefail

mode="${1:-activation-package}"
profile="${XJ_PUBLIC_DOTFILES_HOME_CONFIG:-}"
platform="${XJ_PUBLIC_DOTFILES_HOST_PLATFORM:-}"

if [ -z "$profile" ]; then
  if [ -z "$platform" ]; then
    case "$(uname -m)" in
    arm64)
      platform="aarch64-darwin"
      ;;
    x86_64)
      platform="x86_64-darwin"
      ;;
    *)
      printf 'unsupported Darwin architecture for public Home Manager example: %s\n' "$(uname -m)" >&2
      exit 1
      ;;
    esac
  fi

  case "$platform" in
  aarch64-darwin)
    profile="example"
    ;;
  x86_64-darwin)
    profile="example-x86_64"
    ;;
  *)
    printf 'unsupported public Home Manager host platform: %s\n' "$platform" >&2
    exit 1
    ;;
  esac
fi

case "$profile" in
example | example-x86_64)
  ;;
*)
  printf 'unsupported public Home Manager config: %s\n' "$profile" >&2
  exit 1
  ;;
esac

case "$mode" in
name)
  printf '%s\n' "$profile"
  ;;
config)
  printf '.#homeConfigurations.%s\n' "$profile"
  ;;
activation-package)
  printf '.#homeConfigurations.%s.activationPackage\n' "$profile"
  ;;
*)
  printf 'usage: %s [name|config|activation-package]\n' "$0" >&2
  exit 2
  ;;
esac
