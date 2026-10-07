#!/usr/bin/env bash
# Compare the live home with the activated standalone Home Manager manifest.
set -euo pipefail

[ "$#" -le 1 ] || { printf 'usage: %s [home-directory]\n' "$0" >&2; exit 2; }
home_dir="${1:-$HOME}"
profile="${home_dir}/.local/state/nix/profiles/home-manager"
[ -e "$profile" ] || { printf 'no active Home Manager profile\n' >&2; exit 1; }
manifest="$(readlink -f "$profile/home-files" 2>/dev/null || true)"
[ -d "$manifest" ] || { printf 'active profile has no home-files manifest\n' >&2; exit 1; }

python3 - "$manifest" "$home_dir" <<'PY'
import os
import sys

manifest, home = sys.argv[1:]
leaves = []
for root, dirs, files in os.walk(manifest):
    for name in list(dirs):
        path = os.path.join(root, name)
        if os.path.islink(path):
            dirs.remove(name)
            leaves.append(os.path.relpath(path, manifest))
    leaves.extend(os.path.relpath(os.path.join(root, name), manifest) for name in files)

missing, drifted, unavailable, matched = [], [], [], 0
for relative in sorted(leaves):
    wanted = os.path.join(manifest, relative)
    live = os.path.join(home, relative)
    try:
        os.stat(wanted)
    except OSError:
        unavailable.append((relative, "declared"))
        continue
    if not os.path.lexists(live):
        missing.append(relative)
        continue
    try:
        os.stat(live)
        if os.path.realpath(live) == os.path.realpath(wanted):
            matched += 1
        else:
            drifted.append(relative)
    except OSError:
        unavailable.append((relative, "live"))

for relative in missing:
    print(f"missing: {relative}", file=sys.stderr)
for relative in drifted:
    print(f"drifted: {relative}", file=sys.stderr)
for relative, side in unavailable:
    print(f"unavailable {side} target: {relative}", file=sys.stderr)
if missing or drifted or unavailable:
    print(f"home drift: {matched}/{len(leaves)} match, {len(missing)} missing, "
          f"{len(drifted)} drifted, {len(unavailable)} unavailable", file=sys.stderr)
    raise SystemExit(1)
print(f"home matches the activated generation ({len(leaves)} declared paths)")
PY
