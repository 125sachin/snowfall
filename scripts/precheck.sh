#!/usr/bin/env bash
# Run the same checks as CI before you open a pull request.
# Usage: scripts/precheck.sh [--full]      (--full also builds and runs the tests)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

base="origin/main"
failed=0
step() { printf '\n==> %s\n' "$1"; }
run() { "$@" || failed=1; }

step "Fetching $base"
git fetch --quiet origin main || { echo "cannot fetch origin/main" >&2; exit 1; }

step "Working tree"
if [ -n "$(git status --porcelain)" ]; then echo "uncommitted changes: commit or stash them first" >&2; failed=1; else echo ok; fi

step "Branch name"
run scripts/check_branch_name.sh

step "Up to date with $base"
behind="$(git rev-list --count HEAD.."$base")"
if [ "$behind" -gt 0 ]; then
  echo "branch is $behind commit(s) behind $base: run 'git rebase $base' and resolve any conflicts" >&2
  failed=1
elif ! git merge-tree --write-tree HEAD "$base" >/dev/null 2>&1; then
  echo "branch conflicts with $base: run 'git rebase $base'" >&2
  failed=1
else
  echo ok
fi

step "Commit messages"
for sha in $(git rev-list --no-merges "$base"..HEAD); do
  git log -1 --format=%B "$sha" | scripts/check_commit_msg.sh - || failed=1
done
echo "checked $(git rev-list --no-merges --count "$base"..HEAD) commit(s)"

step "Conflict markers and artifacts"
run scripts/check_conflict_markers.sh "$base"

step "SwiftLint"
if command -v swiftlint >/dev/null; then run swiftlint lint --strict --quiet; else echo "swiftlint not installed (brew install swiftlint); skipped" >&2; fi

if [ "${1:-}" = "--full" ]; then
  step "Build and test"
  run xcodegen generate --quiet
  run xcodebuild -scheme Snowfall -destination 'platform=macOS' test -quiet
fi

echo
if [ "$failed" -eq 0 ]; then echo "All checks passed."; else echo "Some checks failed." >&2; fi
exit "$failed"
