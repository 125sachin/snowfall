#!/usr/bin/env bash
# Validate a branch name against the rules in CONTRIBUTING.md.
# Usage: check_branch_name.sh [branch]      (defaults to the current branch)
set -euo pipefail

TYPES='feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert'
name="${1:-$(git rev-parse --abbrev-ref HEAD)}"

# Long-lived and bot-managed branches.
case "$name" in
  main|HEAD) exit 0 ;;
  dependabot/*) exit 0 ;;
  release/[0-9]*.[0-9]*.[0-9]*) exit 0 ;;
esac

# <type>/<kebab-case-description>, optionally starting with an issue number: fix/123-flicker-on-wake
if printf '%s' "$name" | grep -Eq "^(${TYPES})/([0-9]+-)?[a-z0-9]+(-[a-z0-9]+)*$" && [ "${#name}" -le 60 ]; then
  exit 0
fi

echo "branch name error: '$name'" >&2
echo "  expected: <type>/<short-kebab-case-description>   types: ${TYPES//|/, }" >&2
echo "  examples: feat/reindeer-helper, fix/123-flicker-on-wake, docs/building-guide" >&2
echo "  rules: lowercase letters, digits and hyphens; at most 60 characters. see CONTRIBUTING.md#branch-names" >&2
exit 1
