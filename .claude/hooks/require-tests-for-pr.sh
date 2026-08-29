#!/usr/bin/env bash
set -euo pipefail

cwd=$(jq -r '.cwd // .workspace.current_dir // empty')

if [[ -z "$cwd" ]]; then
  cwd="$PWD"
fi

if [[ -f "$cwd/Taskfile.yml" ]] && command -v task >/dev/null 2>&1; then
  if grep -Eq '^[[:space:]]*(check|verify):' "$cwd/Taskfile.yml"; then
    target=check
    if ! grep -Eq '^[[:space:]]*check:' "$cwd/Taskfile.yml"; then
      target=verify
    fi
    if (cd "$cwd" && task "$target"); then
      exit 0
    fi
    echo "task $target failed. Fix verification failures before creating a PR." >&2
    exit 2
  fi
fi

if [[ -f "$cwd/package.json" ]] && command -v npm >/dev/null 2>&1; then
  if jq -e '.scripts.test? // empty' "$cwd/package.json" >/dev/null 2>&1; then
    if (cd "$cwd" && npm run test --silent); then
      exit 0
    fi
    echo "npm test failed. Fix test failures before creating a PR." >&2
    exit 2
  fi
fi

if [[ -f "$cwd/go.mod" ]] && command -v go >/dev/null 2>&1; then
  if (cd "$cwd" && go test ./...); then
    exit 0
  fi
  echo "go test failed. Fix test failures before creating a PR." >&2
  exit 2
fi

exit 0
