#!/usr/bin/env bash
# setup-hooks.sh — Install the repository's Git hooks into .git/hooks/.
#
# Run once after cloning:
#   ./setup-hooks.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
HOOKS_SRC="${REPO_ROOT}/.github/hooks"
HOOKS_DST="${REPO_ROOT}/.git/hooks"

install_hook() {
  local name="$1"
  local src="${HOOKS_SRC}/${name}"
  local dst="${HOOKS_DST}/${name}"

  if [[ ! -f "$src" ]]; then
    echo "  skip: ${src} not found"
    return
  fi

  cp "$src" "$dst"
  chmod +x "$dst"
  echo "  installed: .git/hooks/${name}"
}

echo "Installing Git hooks…"
install_hook pre-push
echo "Done."
echo
echo "Hooks will run automatically on 'git push'."
echo "To run all checks manually:  ./test.sh"
