#!/usr/bin/env bash
# Validate a commit message against the Conventional Commits rules in CONTRIBUTING.md.
# Usage: check_commit_msg.sh <message-file>      (use "-" to read stdin)
set -euo pipefail

TYPES='feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert'
SUBJECT_RE="^(${TYPES})(\\([a-z0-9][a-z0-9-]*\\))?!?: [a-z0-9\`\"'(\\[].*[^.[:space:]]$"
MAX_SUBJECT=72
MAX_BODY=100

src="${1:--}"
if [ "$src" = "-" ]; then msg="$(cat)"; else msg="$(cat "$src")"; fi

# Ignore comment lines (git adds them in the editor) and trailing blank lines.
msg="$(printf '%s\n' "$msg" | grep -v '^#' || true)"
subject="$(printf '%s\n' "$msg" | head -n 1)"

fail() {
  echo "commit message error: $1" >&2
  echo "  subject: $subject" >&2
  echo "  expected: <type>(<optional-scope>): <description>   types: ${TYPES//|/, }" >&2
  echo "  see CONTRIBUTING.md#commit-messages" >&2
  exit 1
}

# Automatic merge and fixup commits are handled by the pull request, not by this check.
case "$subject" in "Merge "*) exit 0 ;; esac

[ -n "$subject" ] || fail "the message is empty"
[ "${#subject}" -le "$MAX_SUBJECT" ] || fail "the subject is ${#subject} characters; the limit is $MAX_SUBJECT"
printf '%s' "$subject" | grep -Eq "$SUBJECT_RE" ||
  fail "the subject must be '<type>(<scope>): <lowercase imperative description>' with no trailing period"

second="$(printf '%s\n' "$msg" | sed -n '2p')"
[ -z "$second" ] || fail "leave a blank line between the subject and the body"

# Body lines: at most $MAX_BODY characters, except lines that are only a URL or a trailer.
line_no=2
while IFS= read -r line; do
  line_no=$((line_no + 1))
  [ "${#line}" -le "$MAX_BODY" ] && continue
  case "$line" in http*|*"://"*) continue ;; esac
  subject="line $line_no"
  fail "body line is ${#line} characters; wrap lines at $MAX_BODY"
done < <(printf '%s\n' "$msg" | tail -n +3)
