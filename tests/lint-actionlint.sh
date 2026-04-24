#!/usr/bin/env bash
# tests/lint-actionlint.sh — Run actionlint on all GitHub Actions workflow files
# and fail on any violation.  Zero violations are strictly enforced: any error
# causes an immediate CI failure.
# Composite actions referenced from workflows are resolved automatically.
#
# Requires: actionlint binary, or Docker (rhysd/actionlint image is pulled automatically;
#           override via ACTIONLINT_IMAGE env var).
#
# Options:
#   --files <f1> [f2 ...]   Lint specific files (only .github/workflows/ files are used).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ACTIONLINT_VERSION="1.7.12"
ACTIONLINT_IMAGE="${ACTIONLINT_IMAGE:-rhysd/actionlint:${ACTIONLINT_VERSION}}"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
FILES=()
FILES_SPECIFIED=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --update-baseline)
      echo "ERROR: --update-baseline is not supported for actionlint." >&2
      echo "       actionlint violations must be fixed; they cannot be baselined." >&2
      exit 1
      ;;
    --files) FILES_SPECIFIED=true; shift; while [[ $# -gt 0 && "$1" != --* ]]; do FILES+=("$1"); shift; done
      if [[ ${#FILES[@]} -eq 0 ]]; then
        echo "ERROR: --files requires at least one path argument." >&2
        exit 1
      fi
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Build the file list
# ---------------------------------------------------------------------------
if [[ "$FILES_SPECIFIED" == true ]]; then
  # Filter the provided list down to workflow files only.
  # Composite actions are auto-resolved from workflows and must not be passed.
  WORKFLOW_FILES=()
  for f in "${FILES[@]}"; do
    rel="${f#"${REPO_ROOT}/"}"
    case "$rel" in
      .github/workflows/*.yml | .github/workflows/*.yaml)
        WORKFLOW_FILES+=("$f") ;;
    esac
  done
  if [[ ${#WORKFLOW_FILES[@]} -eq 0 ]]; then
    echo "No workflow files in the changed set — skipping actionlint."
    exit 0
  fi
  FILES=("${WORKFLOW_FILES[@]}")
else
  # Auto-discover all workflow files.
  while IFS= read -r file; do
    FILES+=("$file")
  done < <(find "$REPO_ROOT/.github/workflows" -type f \( -name "*.yml" -o -name "*.yaml" \) 2>/dev/null | sort)
fi

# ---------------------------------------------------------------------------
# Ensure actionlint is available
# ---------------------------------------------------------------------------
USE_DOCKER=false
if command -v actionlint &>/dev/null; then
  USE_DOCKER=false
elif command -v docker &>/dev/null; then
  docker pull --quiet "$ACTIONLINT_IMAGE" >/dev/null
  USE_DOCKER=true
else
  echo "ERROR: Neither 'actionlint' nor 'docker' found. Install one to run Actions linting." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Run actionlint and fail on any violation
# ---------------------------------------------------------------------------
echo "Running actionlint on ${#FILES[@]} workflow file(s)…"

# Build relative paths for actionlint (it expects paths relative to repo root).
REL_FILES=()
for f in "${FILES[@]}"; do
  REL_FILES+=("${f#"${REPO_ROOT}/"}")
done

EXIT_CODE=0
if [[ "$USE_DOCKER" == true ]]; then
  docker run --rm \
    -v "${REPO_ROOT}:/repo:ro" \
    -w /repo \
    "$ACTIONLINT_IMAGE" \
    "${REL_FILES[@]}" || EXIT_CODE=$?
else
  (cd "$REPO_ROOT" && actionlint "${REL_FILES[@]}") || EXIT_CODE=$?
fi

# actionlint exit codes: 0 = no issues, 1 = lint errors found, >1 = fatal/internal error
if [[ "$EXIT_CODE" -eq 0 ]]; then
  echo "actionlint: no violations found."
else
  echo "actionlint: violations found. Fix all violations before committing." >&2
  exit "$EXIT_CODE"
fi
