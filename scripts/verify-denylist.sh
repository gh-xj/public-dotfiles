#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

usage() {
  cat <<'USAGE'
Usage: verify-denylist.sh

Scans tracked files and the staged index for identifiers listed in a private
denylist. The denylist path comes from PUBLIC_DENYLIST_FILE, defaulting to
"$HOME/private-config/security/public-denylist.txt". Other clones of this
public repo will not have that file: this script then prints a skip notice
and exits 0, so the check is a no-op for them.

The denylist itself is never read into this script's source or committed
here; only its runtime content is scanned against. On a match, only the
offending file:line is reported -- never the matched line content or which
pattern in the denylist fired -- so this check cannot leak what it forbids.
USAGE
}

if [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

denylist_file="${PUBLIC_DENYLIST_FILE:-$HOME/private-config/security/public-denylist.txt}"

if [ ! -f "$denylist_file" ]; then
  printf 'skipped: no denylist at %s\n' "$denylist_file"
  exit 0
fi

patterns_file="$(mktemp)"
hits_file="$(mktemp)"
cleanup() {
  rm -f "$patterns_file" "$hits_file"
}
trap cleanup EXIT

grep -vE '^[[:space:]]*(#|$)' "$denylist_file" >"$patterns_file" || true

if [ ! -s "$patterns_file" ]; then
  printf 'skipped: denylist at %s has no active patterns\n' "$denylist_file"
  exit 0
fi

: >"$hits_file"

# Tracked working-tree content.
git grep -EIin -f "$patterns_file" -- . 2>/dev/null | cut -d: -f1,2 >>"$hits_file" || true
# Staged index content (catches new/modified files not yet committed).
git grep --cached -EIin -f "$patterns_file" -- . 2>/dev/null | cut -d: -f1,2 >>"$hits_file" || true

sort -u -o "$hits_file" "$hits_file"

if [ -s "$hits_file" ]; then
  printf 'denylist violation(s) found (file:line; pattern and content withheld):\n' >&2
  cat "$hits_file" >&2
  exit 1
fi

printf 'public denylist scan clean\n'
