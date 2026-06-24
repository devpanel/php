#!/usr/bin/env bash
# test.sh — Run all checks locally.
#
# Usage:
#   ./test.sh                    Run all checks.
#   ./test.sh --update-baseline  Re-record current lint results as the new baseline.
#   ./test.sh yaml               Run only YAML lint.
#   ./test.sh shell              Run only shell lint.
#   ./test.sh dockerfile         Run only Dockerfile lint.
#   ./test.sh build              Run only Docker build tests.
#   ./test.sh run                Run only Docker functional (run) tests.
#   ./test.sh build run --version 8.2  Build and run tests for a specific PHP version.
#
# Note: 'run' tests require images to already be built (by the 'build' suite).
# Run 'build' before 'run', or use './test.sh build run --version 8.2'.
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
VERSION_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --update-baseline) EXTRA_ARGS+=(--update-baseline); shift ;;
    yaml|shell|dockerfile|build|run) SUITES+=("$1"); shift ;;
    --version)
      if [[ $# -lt 2 ]]; then
        echo "--version requires a value" >&2; exit 1
      fi
      VERSION_ARGS+=(--version "$2"); shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ ${#SUITES[@]} -eq 0 ]] && SUITES=(yaml shell dockerfile build run)

# ---- runner ---------------------------------------------------------------
FAILED=()

run_suite() {
  local name="$1"
  local script="$2"
  shift 2
  info "Running ${name}…"
  if bash "$script" "$@"; then
    pass "$name passed"
  else
    fail "$name failed"
    FAILED+=("$name")
  fi
  echo
}

echo
echo "========================================"
echo " devpanel/php — lint, build & run checks"
echo "========================================"
echo

for suite in "${SUITES[@]}"; do
  case "$suite" in
    yaml)       run_suite "YAML lint"        "${TESTS_DIR}/lint-yaml.sh" ;;
    shell)      run_suite "Shell lint"       "${TESTS_DIR}/lint-shell.sh"       "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}" ;;
    dockerfile) run_suite "Dockerfile lint"  "${TESTS_DIR}/lint-dockerfile.sh"  "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}" ;;
    build)      run_suite "Docker build"     "${TESTS_DIR}/build-dockerfile.sh" \
                  "${VERSION_ARGS[@]+"${VERSION_ARGS[@]}"}" ;;
    run)        run_suite "Docker run"       "${TESTS_DIR}/run-dockerfile.sh"   \
                  "${VERSION_ARGS[@]+"${VERSION_ARGS[@]}"}" ;;
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
