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

# Derive PLATFORM_KEY from the target platform so the test build uses the same
# GHA/GHCR cache scopes as the CI build matrix job for the same platform (e.g.
# "php83-base-linux-amd64" instead of the unkeyed "php83-base").  This lets the
# test job hit the caches already populated by the corresponding build job.
PLATFORM_KEY="${PLATFORMS//\//-}"

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
#   PLATFORM_KEY         Matches the key used by the build matrix job for this
#                        platform so the test reads from the same cache scopes.
#   DOWNLOADS_DIR        Path to a directory whose pre-downloaded/ subdirectory
#                        contains pre-seeded artifacts.  When set by CI to a
#                        runner-local directory populated by actions/cache@v5,
#                        the downloader stage uses cached files instead of
#                        re-downloading.  When empty (default), the Dockerfile's
#                        'downloads' stage (FROM alpine:3 with an empty
#                        /pre-downloaded dir) is used as the fallback.
#   BAKE_OVERRIDES_FILE  Path to a JSON bake-override file generated by the
#                        preseed-downloads composite action.  When set, it is
#                        passed as an additional --file argument so each
#                        phpX_Y-downloader target receives the correct
#                        code-server/Copilot Chat version and SHA256 args for
#                        its Debian tier.  When unset, the Dockerfile ARG
#                        defaults are used as fallback.
#
# --load:
#   Import built images into the local Docker daemon so that run-dockerfile.sh
#   can run functional tests against them (requires single-platform build).
BAKE_ENV=(
  VERSIONS="$VERSIONS_LIST"
  VERSIONS_BASE="$VERSIONS_LIST"
  VERSIONS_SECURE="$VERSIONS_LIST"
  REPO="$TEST_REPO"
  GHCR_REPO="$TEST_REPO"
  TAG_SUFFIX=""
  PLATFORMS="$PLATFORMS"
  PLATFORM_KEY="$PLATFORM_KEY"
  "CACHE_FROM_ENABLED=${CACHE_FROM_ENABLED:-false}"
  GHCR_WRITABLE=false
)
[ -n "${DOWNLOADS_DIR:-}" ] && BAKE_ENV+=( "DOWNLOADS_DIR=${DOWNLOADS_DIR}" )

# Build the list of bake files: always include docker-bake.hcl; add the
# preseed-downloads JSON override file when CI provides it.
BAKE_FILES=( --file "$REPO_ROOT/docker-bake.hcl" )
if [ -n "${BAKE_OVERRIDES_FILE:-}" ]; then
  [ -f "$BAKE_OVERRIDES_FILE" ] || {
    echo "Error: BAKE_OVERRIDES_FILE='${BAKE_OVERRIDES_FILE}' does not exist." >&2; exit 1
  }
  BAKE_FILES+=( --file "$BAKE_OVERRIDES_FILE" )
fi

# BUILDX_BAKE_ENTITLEMENTS_FS=0 bypasses the filesystem entitlement check
# introduced in buildx v0.32.1 for bake files that reference local filesystem
# paths as named contexts (i.e. when DOWNLOADS_DIR is set).  The check is
# non-deterministic — the same invocation passes or fails across runner
# environments without any code change — so we disable it here to match the
# behaviour of the build-php-images composite action.
env "${BAKE_ENV[@]}" \
BUILDX_BAKE_ENTITLEMENTS_FS=0 \
docker buildx bake \
  "${BAKE_FILES[@]}" \
  --load

echo "All Docker builds passed."
