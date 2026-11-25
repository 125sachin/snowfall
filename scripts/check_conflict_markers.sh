#!/usr/bin/env bash
# Fail if the changes against a base ref add merge conflict markers or build artifacts.
# Usage: check_conflict_markers.sh [base-ref]      (defaults to origin/main)
set -euo pipefail

base="${1:-origin/main}"
status=0

if git diff "$base"...HEAD -U0 --diff-filter=AM | grep -En '^\+(<<<<<<< |=======$|>>>>>>> )' >/dev/null; then
  echo "conflict markers found in the changes against $base:" >&2
  git diff "$base"...HEAD -U0 --diff-filter=AM | grep -En '^\+(<<<<<<< |=======$|>>>>>>> )' >&2 || true
  status=1
fi

added="$(git diff "$base"...HEAD --name-only --diff-filter=A)"
if printf '%s\n' "$added" | grep -Eq '(^|/)(\.DS_Store|build/|dist/|DerivedData/)|\.(dmg|app|xcuserstate)$'; then
  echo "build artifacts or system files must not be committed:" >&2
  printf '%s\n' "$added" | grep -E '(^|/)(\.DS_Store|build/|dist/|DerivedData/)|\.(dmg|app|xcuserstate)$' >&2
  status=1
fi
exit "$status"
