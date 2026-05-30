#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

scan_home=0
maxdepth=3
limit=120
slow_limit=20
paths=()
starship_bin=""

usage() {
  cat <<'EOF'
Usage: task starship:diagnose -- [PATH ...] [--scan-home] [--maxdepth N] [--limit N]

Examples:
  task starship:diagnose
  task starship:diagnose -- "$PWD"
  task starship:diagnose -- ~/Downloads ~/github
  task starship:diagnose -- --scan-home --maxdepth 3 --limit 120

Options:
  --scan-home  Scan a child-count-heavy sample of directories under $HOME.
  --maxdepth N Depth for --scan-home, default 3.
  --limit N    Number of high child-count directories to scan, default 120.
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$1" >&2
    exit 127
  }
}

measure_prompt_ms() {
  local path="$1"
  local err_file="$2"

  zsh -f -c '
zmodload zsh/datetime
path=$1
starship_bin=$2
start=$EPOCHREALTIME
NO_COLOR=1 "$starship_bin" prompt --path "$path" --logical-path "$path" --terminal-width=100 >/dev/null
rc=$?
end=$EPOCHREALTIME
printf "%.3f\t%d\n" "$(( (end - start) * 1000 ))" "$rc"
' _ "$path" "$starship_bin" 2>"$err_file"
}

print_config_summary() {
  printf '== starship config ==\n'
  printf 'binary: %s\n' "$starship_bin"
  printf 'version: %s\n' "$("$starship_bin" --version)"
  printf 'config: %s\n' "${STARSHIP_CONFIG:-$HOME/.config/starship.toml}"
  "$starship_bin" print-config | sed -nE '/^(scan_timeout|command_timeout) =/p'
}

diagnose_path() {
  local path="$1"
  local err_file
  local timing_err_file
  local measure
  local ms
  local rc

  if [[ ! -d "$path" ]]; then
    printf '\n== %s ==\n' "$path"
    printf 'status: skipped, not a directory\n'
    return 0
  fi

  err_file="$(mktemp)"
  timing_err_file="$(mktemp)"

  measure="$(measure_prompt_ms "$path" "$err_file")"
  ms="${measure%%$'\t'*}"
  rc="${measure##*$'\t'}"

  printf '\n== %s ==\n' "$path"
  printf 'prompt_ms: %s\n' "$ms"
  printf 'prompt_exit: %s\n' "$rc"

  if [[ -s "$err_file" ]]; then
    printf 'prompt_stderr:\n'
    sed 's/^/  /' "$err_file"
  else
    printf 'prompt_stderr: none\n'
  fi

  printf 'module_timings:\n'
  if ! NO_COLOR=1 "$starship_bin" timings --path "$path" --logical-path "$path" --terminal-width=100 2>"$timing_err_file" | sed 's/^/  /'; then
    printf '  starship timings failed\n'
  fi
  if [[ -s "$timing_err_file" ]]; then
    printf 'timings_stderr:\n'
    sed 's/^/  /' "$timing_err_file"
  fi

  rm -f "$err_file" "$timing_err_file"
}

scan_home_dirs() {
  local dirs_file
  local results_file
  local warnings_file
  local path
  local count
  local err_file
  local measure
  local ms
  local rc
  local warn

  dirs_file="$(mktemp)"
  results_file="$(mktemp)"
  warnings_file="$(mktemp)"

  printf '\n== home scan candidate selection ==\n'
  printf 'home: %s\n' "$HOME"
  printf 'maxdepth: %s\n' "$maxdepth"
  printf 'limit: %s\n' "$limit"

  while IFS= read -r -d '' path; do
    count="$(find "$path" -mindepth 1 -maxdepth 1 -print 2>/dev/null | wc -l | tr -d ' ')"
    printf '%s\t%s\n' "$count" "$path"
  done < <(find "$HOME" -maxdepth "$maxdepth" -type d -print0 2>/dev/null) |
    sort -rn -k1,1 |
    head -n "$limit" >"$dirs_file"

  printf '\n== home scan prompt timings ==\n'
  while IFS=$'\t' read -r count path; do
    err_file="$(mktemp)"
    measure="$(measure_prompt_ms "$path" "$err_file")"
    ms="${measure%%$'\t'*}"
    rc="${measure##*$'\t'}"
    warn=0
    if [[ -s "$err_file" ]]; then
      warn=1
      {
        printf '== %s ==\n' "$path"
        sed 's/^/  /' "$err_file"
      } >>"$warnings_file"
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$ms" "$rc" "$warn" "$count" "$path" >>"$results_file"
    rm -f "$err_file"
  done <"$dirs_file"

  printf 'slowest_paths:\n'
  sort -rn -k1,1 "$results_file" |
    head -n "$slow_limit" |
    awk -F '\t' '{ printf "  %6.1f ms  rc=%s  warn=%s  children=%s  %s\n", $1, $2, $3, $4, $5 }'

  if [[ -s "$warnings_file" ]]; then
    printf '\nwarnings:\n'
    cat "$warnings_file"
  else
    printf '\nwarnings: none\n'
  fi

  rm -f "$dirs_file" "$results_file" "$warnings_file"
}

while (($#)); do
  case "$1" in
    --scan-home)
      scan_home=1
      shift
      ;;
    --maxdepth)
      maxdepth="${2:?--maxdepth requires a value}"
      shift 2
      ;;
    --limit)
      limit="${2:?--limit requires a value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      printf 'unknown argument: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      paths+=("$1")
      shift
      ;;
  esac
done

while (($#)); do
  paths+=("$1")
  shift
done

need_cmd starship
need_cmd zsh
need_cmd find
need_cmd sort
need_cmd awk
starship_bin="$(command -v starship)"

print_config_summary

if ((${#paths[@]} == 0)); then
  paths=("$PWD")
fi

for path in "${paths[@]}"; do
  diagnose_path "$path"
done

if ((scan_home)); then
  scan_home_dirs
fi
