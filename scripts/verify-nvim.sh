#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
nvim --headless --cmd "set rtp^=$repo_root/.config/nvim" -u "$repo_root/.config/nvim/init.lua" '+qa'
