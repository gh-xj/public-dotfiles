#!/usr/bin/env bash
set -euo pipefail
# Keep a portable shell entrypoint; Python handles process records consistently.
exec python3 "$(dirname "${BASH_SOURCE[0]}")/nvim-health.py" "$@"
