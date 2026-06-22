#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bash -n "$repo_root/scripts/patchkit"

workdir="$tmpdir/work"
mkdir -p "$workdir"
git -C "$workdir" init -q
printf 'one\n' > "$workdir/f.txt"

patch_file="$tmpdir/change.diff"
cat > "$patch_file" <<'DIFF'
diff --git a/f.txt b/f.txt
index 5626abf..f719efd 100644
--- a/f.txt
+++ b/f.txt
@@ -1 +1 @@
-one
+two
DIFF

"$repo_root/scripts/patchkit" --repo "$workdir" --check < "$patch_file"

apply_patch="$tmpdir/apply_patch"
ln -s "$repo_root/scripts/patchkit" "$apply_patch"
"$apply_patch" --repo "$workdir" < "$patch_file"

if [ "$(cat "$workdir/f.txt")" != "two" ]; then
  printf 'patchkit did not apply the expected file change\n' >&2
  exit 1
fi

codex_payload="$tmpdir/codex-apply-patch.txt"
cat > "$codex_payload" <<'PATCH_PAYLOAD'
*** Begin Patch
*** Update File: f.txt
@@
-two
+three
*** End Patch
PATCH_PAYLOAD

if "$repo_root/scripts/patchkit" --repo "$workdir" < "$codex_payload" 2>/dev/null; then
  printf 'patchkit accepted a Codex apply_patch payload unexpectedly\n' >&2
  exit 1
fi

echo "patchkit behavior verified"
