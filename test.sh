#!/usr/bin/env bash
# test.sh — Run all lint checks locally.
#
# Usage:
#   ./test.sh                  Run all checks.
#   ./test.sh --update-baseline  Re-record current results as the new baseline.
#   ./test.sh yaml             Run only YAML lint.
#   ./test.sh shell            Run only shell lint.
#   ./test.sh dockerfile       Run only Dockerfile lint.
#
# Exit code:  0 = all checks passed  |  non-zero = one or more checks failed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
TESTS_DIR="${REPO_ROOT}/tests"

# ---- colour helpers -------------------------------------------------------
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RESET=$'\033[0m'
pass() { printf '%s  ✔ %s%s\n' "$GREEN" "$*" "$RESET"; }
fail() { printf '%s  ✘ %s%s\n' "$RED" "$*" "$RESET"; }
info() { printf '%s  ▸ %s%s\n' "$YELLOW" "$*" "$RESET"; }

# ---- argument handling ----------------------------------------------------
SUITES=()
EXTRA_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --update-baseline) EXTRA_ARGS+=(--update-baseline) ;;
    yaml|shell|dockerfile) SUITES+=("$arg") ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

[[ ${#SUITES[@]} -eq 0 ]] && SUITES=(yaml shell dockerfile)

# ---- runner ---------------------------------------------------------------
FAILED=()

run_suite() {
  local name="$1"
  local script="$2"
  info "Running $name lint…"
  if bash "$script" "${EXTRA_ARGS[@]}"; then
    pass "$name lint passed"
  else
    fail "$name lint failed"
    FAILED+=("$name")
  fi
  echo
}

echo
echo "========================================"
echo " devpanel/php — lint checks"
echo "========================================"
echo

for suite in "${SUITES[@]}"; do
  case "$suite" in
    yaml)       run_suite "YAML"       "${TESTS_DIR}/lint-yaml.sh" ;;
    shell)      run_suite "Shell"      "${TESTS_DIR}/lint-shell.sh" ;;
    dockerfile) run_suite "Dockerfile" "${TESTS_DIR}/lint-dockerfile.sh" ;;
  esac
done

echo "========================================"
if [[ ${#FAILED[@]} -eq 0 ]]; then
  printf '%s%s%s\n' "$GREEN" "All checks passed." "$RESET"
  exit 0
else
  printf '%s%s %s%s\n' "$RED" "Failed checks:" "${FAILED[*]}" "$RESET"
  exit 1
fi
