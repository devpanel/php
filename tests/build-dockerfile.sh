#!/usr/bin/env bash
# tests/build-dockerfile.sh — Build Docker images using docker-bake.hcl to
# verify they build successfully.  Does NOT push any images.
#
# Delegates to docker-bake.hcl (the production bake file) so that tests
# exercise the same build paths as CI.  Built images are loaded into the local
# Docker daemon tagged as devpanel-php-test:<version>-<stage> so that
# tests/run-dockerfile.sh can run functional tests against them.
#
# Environment variables:
#   GITHUB_TOKEN    Optional; forwarded to the downloader build stage for
#                   authenticated GitHub API calls.
#   PLATFORMS       Target platform(s).  Defaults to the current host platform.
#                   Must be a single platform to use --load.
#
# Options:
#   --version <v>           Build all variants for a single PHP version (e.g. 8.2).
#   --files <f1> [f2 ...]   Build the variants that own those Dockerfiles
#                           (dependency chain is always honoured).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Image namespace for locally loaded test images.  Must match TAG_PREFIX in
# run-dockerfile.sh so that the two scripts agree on image names.
TEST_REPO="devpanel-php-test"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
TARGET_VERSION=""
EXTRA_FILES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
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
# Determine which PHP versions to build
# ---------------------------------------------------------------------------
if [[ -n "$TARGET_VERSION" ]]; then
  VERSIONS_LIST="$TARGET_VERSION"
else
  DETECT_ARGS=()
  [[ ${#EXTRA_FILES[@]} -gt 0 ]] && DETECT_ARGS=(--files "${EXTRA_FILES[@]}")
  VERSIONS_LIST="$(bash "$REPO_ROOT/tests/detect-versions.sh" \
    "${DETECT_ARGS[@]+"${DETECT_ARGS[@]}"}" | sort -V | tr '\n' ' ' | xargs)"
fi

if [[ -z "$VERSIONS_LIST" ]]; then
  echo "No PHP versions to build." >&2
  exit 1
fi

echo "Building Docker images for PHP version(s): ${VERSIONS_LIST}"

# ---------------------------------------------------------------------------
# Ensure Docker (with buildx) is available
# ---------------------------------------------------------------------------
if ! command -v docker &>/dev/null; then
  echo "ERROR: 'docker' is required to run build tests." >&2
  exit 1
fi
if ! docker buildx version &>/dev/null; then
  echo "ERROR: 'docker buildx' is required to run build tests." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Detect highest PHP version (used as LATEST_PHP_VERSION in bake)
# ---------------------------------------------------------------------------
LATEST_PHP_VERSION="$(echo "$VERSIONS_LIST" | tr ' ' '\n' | sort -V | tail -1)"

# ---------------------------------------------------------------------------
# Detect target platform (single platform required for --load)
# ---------------------------------------------------------------------------
if [[ -z "${PLATFORMS:-}" ]]; then
  arch="$(uname -m)"
  case "$arch" in
    x86_64)        PLATFORMS="linux/amd64" ;;
    aarch64|arm64) PLATFORMS="linux/arm64" ;;
    *)             PLATFORMS="linux/amd64" ;;
  esac
fi

# --load requires a single platform; reject multi-platform values early.
if [[ "$PLATFORMS" == *","* || "$PLATFORMS" == *" "* ]]; then
  echo "Error: PLATFORMS must be a single platform when using --load (got: $PLATFORMS)." >&2
  echo "       Set PLATFORMS to one of: linux/amd64, linux/arm64, etc." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Build using docker-bake.hcl in test mode
# ---------------------------------------------------------------------------
# Test-mode overrides:
#   REPO/GHCR_REPO       Use a local test namespace; no real registry is pushed.
#   VERSIONS_BASE/SECURE Set equal to VERSIONS so every version's stages build.
#   TAG_SUFFIX           Empty; tags match run-dockerfile.sh's TAG_PREFIX.
#   CACHE_FROM_ENABLED   Defaults to false (clean build from source) for local
#                        runs.  Set to true (e.g. in CI) to read from GHA cache
#                        and benefit from layer reuse on re-runs.
#   GHCR_WRITABLE        false; registry cache write failures are non-fatal
#                        (ignore-error=true).  GHA cache writes are unconditional
#                        and unaffected by this flag.
#   GITHUB_TOKEN         Forwarded so the downloader stage can call the GitHub
#                        API to resolve CODESERVER_VERSION when not pinned.
#
# --load:
#   Import built images into the local Docker daemon so that run-dockerfile.sh
#   can run functional tests against them (requires single-platform build).
VERSIONS="$VERSIONS_LIST" \
VERSIONS_BASE="$VERSIONS_LIST" \
VERSIONS_SECURE="$VERSIONS_LIST" \
REPO="$TEST_REPO" \
GHCR_REPO="$TEST_REPO" \
TAG_SUFFIX="" \
LATEST_PHP_VERSION="$LATEST_PHP_VERSION" \
PLATFORMS="$PLATFORMS" \
CACHE_FROM_ENABLED="${CACHE_FROM_ENABLED:-false}" \
GHCR_WRITABLE=false \
GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
docker buildx bake \
  --file "$REPO_ROOT/docker-bake.hcl" \
  --load

echo "All Docker builds passed."

