#!/usr/bin/env bash
# setup-hooks.sh — Configure Git to use the repository's .githooks directory.
#
# Run once after cloning:
#   ./setup-hooks.sh
#
# This sets core.hooksPath in the local Git config so that Git picks up the
# hooks in .githooks/ directly, without copying files into .git/hooks/.
# The hooks are therefore always in sync with the repository source.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

git -C "$REPO_ROOT" config core.hooksPath .githooks
echo "Git hooks configured: core.hooksPath = .githooks"
echo
echo "Hooks will run automatically on 'git push'."
echo "To run all checks manually:  ./test.sh"
