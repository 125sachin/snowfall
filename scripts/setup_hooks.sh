#!/usr/bin/env bash
# Enable the repository's git hooks and commit message template for this clone.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
git config core.hooksPath .githooks
git config commit.template .gitmessage
echo "Hooks enabled: commit messages and branch names are checked locally."
