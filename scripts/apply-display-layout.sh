#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
layouts_file="$repo_root/config/macos/display-layouts.tsv"
mode="apply"

usage() {
  cat <<'EOF'
Usage: scripts/apply-display-layout.sh [--apply|--verify|--dry-run]

Apply or verify known public display layouts from config/macos/display-layouts.tsv.
Unknown displays are skipped so the task stays portable across machines.
EOF
}

die() {
  printf 'display-layout: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '==> %s\n' "$*" >&2
}

find_cmd() {
  local name="$1"
  local candidate

  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi

  for candidate in \
    "/opt/homebrew/bin/$name" \
    "/usr/local/bin/$name"
  do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --apply)
        mode="apply"
        ;;
      --verify)
        mode="verify"
        ;;
      --dry-run)
        mode="dry-run"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown option: $1"
        ;;
    esac
    shift
  done
}

current_display_field() {
  local serial="$1"
  local field="$2"
  local list_output="$3"

  awk -v serial="$serial" -v field="$field" '
    /^Persistent screen id:/ { found = 0 }
    $0 == "Serial screen id: " serial { found = 1; next }
    found && field == "res" && /^Resolution:/ { print $2; exit }
    found && field == "hz" && /^Hertz:/ { print $2; exit }
    found && field == "color_depth" && /^Color Depth:/ { print $3; exit }
    found && field == "scaling" && /^Scaling:/ { print $2; exit }
    found && field == "origin" && /^Origin:/ { print $2; exit }
    found && field == "degree" && /^Rotation:/ { print $2; exit }
    found && field == "enabled" && /^Enabled:/ { print $2; exit }
  ' <<<"$list_output"
}

verify_field() {
  local serial="$1"
  local label="$2"
  local field="$3"
  local expected="$4"
  local actual="$5"

  if [ "$actual" != "$expected" ]; then
    printf 'display layout mismatch for %s (%s): %s expected %s got %s\n' "$label" "$serial" "$field" "$expected" "${actual:-<unset>}" >&2
    return 1
  fi
}

main() {
  local displayplacer_cmd list_output matched=0 failures=0
  local serial label res hz color_depth scaling origin degree actual arg

  parse_args "$@"

  [ "$(uname -s)" = "Darwin" ] || {
    echo "display layout skipped on non-Darwin host"
    exit 0
  }
  [ -f "$layouts_file" ] || die "missing layout file: $layouts_file"

  displayplacer_cmd="$(find_cmd displayplacer || true)"
  [ -n "$displayplacer_cmd" ] || die "displayplacer is required; run the nix-darwin/Homebrew phase first"

  list_output="$("$displayplacer_cmd" list)"

  while IFS=$'\t' read -r serial label res hz color_depth scaling origin degree; do
    case "$serial" in
      ""|\#*)
        continue
        ;;
    esac

    actual="$(current_display_field "$serial" enabled "$list_output")"
    [ -n "$actual" ] || continue

    matched=$((matched + 1))
    arg="id:$serial res:$res hz:$hz color_depth:$color_depth enabled:true scaling:$scaling origin:$origin degree:$degree"

    case "$mode" in
      apply)
        info "applying display layout for $label ($serial): $res @ ${hz}Hz"
        "$displayplacer_cmd" "$arg"
        ;;
      dry-run)
        printf 'displayplacer %q\n' "$arg"
        ;;
      verify)
        verify_field "$serial" "$label" res "$res" "$(current_display_field "$serial" res "$list_output")" || failures=$((failures + 1))
        verify_field "$serial" "$label" hz "$hz" "$(current_display_field "$serial" hz "$list_output")" || failures=$((failures + 1))
        verify_field "$serial" "$label" color_depth "$color_depth" "$(current_display_field "$serial" color_depth "$list_output")" || failures=$((failures + 1))
        verify_field "$serial" "$label" scaling "$scaling" "$(current_display_field "$serial" scaling "$list_output")" || failures=$((failures + 1))
        verify_field "$serial" "$label" origin "$origin" "$(current_display_field "$serial" origin "$list_output")" || failures=$((failures + 1))
        verify_field "$serial" "$label" degree "$degree" "$(current_display_field "$serial" degree "$list_output")" || failures=$((failures + 1))
        ;;
    esac
  done <"$layouts_file"

  if [ "$matched" -eq 0 ]; then
    echo "display layout skipped; no known display serials found"
    exit 0
  fi

  if [ "$mode" = "verify" ]; then
    [ "$failures" -eq 0 ] || exit 1
    echo "display layout baseline verified"
  fi
}

main "$@"
