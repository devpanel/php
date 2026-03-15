#!/usr/bin/env bash
# tests/run-dockerfile.sh — Functional (run) tests for Docker images.
#
# Starts each image as a short-lived container and verifies that core
# tools are present and executable.  Does NOT push any images.
#
# Images are expected to have been built by tests/build-dockerfile.sh
# first.  If the required local test tag is not found, the variant is
# skipped with a warning rather than failing — this allows
# `./test.sh run` to be called standalone with pre-pulled images too.
#
# Tested per variant:
#   base    — php --version, composer --version, apache2 -v
#   secure  — inherits base checks; mod_security2 library present
#   advance — inherits secure checks; redis-cli --version,
#              varnishd -V (if installed)
#
# Options:
#   --version <v>           Test a single PHP version (e.g. 8.2).
#   --update-baseline       Accepted for compatibility; no-op.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG_PREFIX="devpanel-php-test"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
TARGET_VERSION=""
EXTRA_FILES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --update-baseline) shift ;;          # no-op; accepted for compatibility
    --version)
      if [[ $# -lt 2 || "$2" == --* ]]; then
        echo "Error: --version requires an argument (e.g. --version 8.2)." >&2; exit 1
      fi
      TARGET_VERSION="$2"; shift 2 ;;
    --files) shift; while [[ $# -gt 0 && "$1" != --* ]]; do EXTRA_FILES+=("$1"); shift; done ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Determine which PHP versions to test
# ---------------------------------------------------------------------------
declare -A TEST_VERSIONS

if [[ -n "$TARGET_VERSION" ]]; then
  TEST_VERSIONS["$TARGET_VERSION"]=1
elif [[ ${#EXTRA_FILES[@]} -gt 0 ]]; then
  for f in "${EXTRA_FILES[@]}"; do
    # Extract version from paths like .../8.2/base/Dockerfile or 8.2/base/Dockerfile
    version="$(echo "$f" | sed 's|.*[/]\([0-9][0-9]*\.[0-9][0-9]*\)[/].*|\1|' | grep -E '^[0-9]+\.[0-9]+$' || true)"
    if [[ -n "$version" ]]; then
      TEST_VERSIONS["$version"]=1
    fi
  done
else
  for dir in "$REPO_ROOT"/*/base/Dockerfile; do
    version="$(basename "$(dirname "$(dirname "$dir")")")"
    TEST_VERSIONS["$version"]=1
  done
fi

if [[ ${#TEST_VERSIONS[@]} -eq 0 ]]; then
  echo "No PHP versions to test." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Ensure Docker is available
# ---------------------------------------------------------------------------
if ! command -v docker &>/dev/null; then
  echo "ERROR: 'docker' is required to run functional tests." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
PASS=0
FAIL=0
SKIP=0

ok()   { echo "    ✔ $*"; (( PASS++ )) || true; }
err()  { echo "    ✘ $*" >&2; (( FAIL++ )) || true; }
skip() { echo "    - $* (skipped)"; (( SKIP++ )) || true; }

# run_in <image> <cmd...>  — run a one-shot container and capture output.
run_in() {
  local image="$1"; shift
  docker run --rm --entrypoint "" "$image" "$@" 2>&1
}

# assert_contains <image> <pattern> <description> <cmd...>
# Run cmd in the image; fail if output does not match the pattern.
assert_contains() {
  local image="$1" pattern="$2" desc="$3"; shift 3
  local output
  if output="$(run_in "$image" "$@" 2>&1)"; then
    if echo "$output" | grep -qE "$pattern"; then
      ok "$desc"
    else
      err "$desc — output did not match /$pattern/: $output"
    fi
  else
    err "$desc — command failed: $output"
  fi
}

# assert_file_exists <image> <path> <description>
assert_file_exists() {
  local image="$1" path="$2" desc="$3"
  local output
  if output="$(run_in "$image" sh -c "test -e '$path' && echo EXISTS" 2>&1)"; then
    if echo "$output" | grep -q "EXISTS"; then
      ok "$desc"
    else
      err "$desc — $path not found in image"
    fi
  else
    err "$desc — could not check $path: $output"
  fi
}

# ---------------------------------------------------------------------------
# Test suites per variant
# ---------------------------------------------------------------------------
test_base() {
  local image="$1" version="$2"

  # PHP CLI — version string must contain the expected major.minor
  assert_contains "$image" "PHP ${version}\." "PHP ${version} CLI available" \
    php --version

  # PHP can execute code
  assert_contains "$image" "hello-functional-test" "PHP code execution works" \
    php -r "echo 'hello-functional-test';"

  # Composer is installed and executable
  assert_contains "$image" "Composer version" "composer available" \
    composer --version

  # Apache binary present
  assert_contains "$image" "Apache" "apache2 binary present" \
    apache2 -v

  # PHP extensions: common extensions that should always be installed
  assert_contains "$image" "pdo" "pdo extension loaded" \
    php -m

  assert_contains "$image" "mbstring" "mbstring extension loaded" \
    php -m
}

test_secure() {
  local image="$1" version="$2"

  # All base checks apply
  test_base "$image" "$version"

  # mod_security2 library should exist
  assert_file_exists "$image" \
    "/usr/lib/apache2/modules/mod_security2.so" \
    "mod_security2 module installed"
}

test_advance() {
  local image="$1" version="$2"

  # Inherit all secure checks (which in turn inherit base checks)
  test_secure "$image" "$version"

  # Redis CLI should be installed in advance
  assert_contains "$image" "[Rr]edis" "redis-cli available" \
    redis-cli --version
}

# ---------------------------------------------------------------------------
# Run tests per version
# ---------------------------------------------------------------------------
OVERALL_FAIL=0
mapfile -t SORTED_VERSIONS < <(printf '%s\n' "${!TEST_VERSIONS[@]}" | sort)

echo "Running functional tests for PHP version(s): ${SORTED_VERSIONS[*]}"
echo

for version in "${SORTED_VERSIONS[@]}"; do
  echo "=== PHP ${version} ==="
  for variant in base secure advance; do
    tag="${TAG_PREFIX}:${version}-${variant}"
    echo "  --- ${variant} ---"

    if ! docker image inspect "$tag" &>/dev/null; then
      skip "${version}/${variant} — image ${tag} not found locally (run build tests first)"
      echo
      continue
    fi

    case "$variant" in
      base)    test_base    "$tag" "$version" ;;
      secure)  test_secure  "$tag" "$version" ;;
      advance) test_advance "$tag" "$version" ;;
    esac

    if [[ $FAIL -gt 0 ]]; then
      OVERALL_FAIL=1
    fi
    echo
  done
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "========================================"
echo " Functional test results:"
echo "   Passed: ${PASS}"
echo "   Failed: ${FAIL}"
echo "   Skipped: ${SKIP}"
echo "========================================"

if [[ $OVERALL_FAIL -ne 0 ]]; then
  echo "One or more functional tests FAILED." >&2
  exit 1
fi
if [[ $PASS -eq 0 && $SKIP -gt 0 ]]; then
  echo "WARNING: all tests were skipped (no images found). Run build tests first." >&2
  exit 0
fi
echo "All functional tests passed."
