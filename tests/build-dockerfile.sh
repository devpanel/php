#!/usr/bin/env bash
# tests/build-dockerfile.sh — Build Docker images to verify they build
# successfully.  Does NOT push any images.
#
# Each PHP version has three variants that must be built in order:
#   base  ← FROM php:<version>-apache  (no external devpanel dependency)
#   secure ← FROM devpanel/php:<version>-base
#   advance ← FROM devpanel/php:<version>-secure
#
# This script builds base first, tags it locally, then builds secure using
# the locally-built base, and finally builds advance using locally-built
# secure.  All test tags are cleaned up on exit.
#
# Options:
#   --version <v>           Build all variants for a single PHP version (e.g. 8.2).
#   --files <f1> [f2 ...]   Build the variants that own those Dockerfiles
#                           (dependency chain is always honoured).
#   --update-baseline       Accepted for compatibility; has no effect (builds are
#                           pass/fail — there is no baseline to update).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Local image tag prefix used only during this test run.
TAG_PREFIX="devpanel-php-test"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
TARGET_VERSION=""
EXTRA_FILES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --update-baseline) shift ;;          # no-op; accepted for compatibility
    --version) TARGET_VERSION="$2"; shift 2 ;;
    --files) shift; while [[ $# -gt 0 && "$1" != --* ]]; do EXTRA_FILES+=("$1"); shift; done ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Determine which PHP versions to build
# ---------------------------------------------------------------------------
declare -A BUILD_VERSIONS   # key = version string, value = 1

if [[ -n "$TARGET_VERSION" ]]; then
  BUILD_VERSIONS["$TARGET_VERSION"]=1
elif [[ ${#EXTRA_FILES[@]} -gt 0 ]]; then
  for f in "${EXTRA_FILES[@]}"; do
    # Extract version from paths like .../8.2/base/Dockerfile
    version="$(echo "$f" | grep -oP '(?<=/|^)\d+\.\d+(?=/)' | head -1 || true)"
    if [[ -n "$version" ]]; then
      BUILD_VERSIONS["$version"]=1
    fi
  done
else
  # Build all versions found in the repo.
  for dir in "$REPO_ROOT"/*/base/Dockerfile; do
    version="$(basename "$(dirname "$(dirname "$dir")")")"
    BUILD_VERSIONS["$version"]=1
  done
fi

if [[ ${#BUILD_VERSIONS[@]} -eq 0 ]]; then
  echo "No PHP versions to build." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Ensure Docker is available
# ---------------------------------------------------------------------------
if ! command -v docker &>/dev/null; then
  echo "ERROR: 'docker' is required to run build tests." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Cleanup: remove locally-created test tags on exit
# ---------------------------------------------------------------------------
CREATED_TAGS=()
cleanup() {
  if [[ ${#CREATED_TAGS[@]} -gt 0 ]]; then
    echo "Removing local test images…"
    for tag in "${CREATED_TAGS[@]}"; do
      docker rmi --force "$tag" 2>/dev/null || true
    done
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Build helper
# ---------------------------------------------------------------------------
FAILED=0

build_variant() {
  local version="$1"
  local variant="$2"   # base | secure | advance
  local context="${REPO_ROOT}/${version}/${variant}"
  local dockerfile="${context}/Dockerfile"

  if [[ ! -f "$dockerfile" ]]; then
    echo "  skip: ${version}/${variant}/Dockerfile not found"
    return
  fi

  local tag="${TAG_PREFIX}:${version}-${variant}"

  # For dependent variants, override BASE_IMAGE to use our locally-built tag.
  local build_args=()
  case "$variant" in
    secure)  build_args=(--build-arg "BASE_IMAGE=${TAG_PREFIX}:${version}-base") ;;
    advance) build_args=(--build-arg "BASE_IMAGE=${TAG_PREFIX}:${version}-secure") ;;
  esac

  echo "  Building ${version}/${variant}…"
  if docker build \
      --quiet \
      "${build_args[@]+"${build_args[@]}"}" \
      --tag "$tag" \
      "$context" > /dev/null; then
    CREATED_TAGS+=("$tag")
    echo "  ✔ ${version}/${variant} built successfully"
  else
    echo "  ✘ ${version}/${variant} build FAILED" >&2
    FAILED=1
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Build each version
# ---------------------------------------------------------------------------
# Sort versions for deterministic output.
mapfile -t SORTED_VERSIONS < <(printf '%s\n' "${!BUILD_VERSIONS[@]}" | sort)

echo "Building Docker images for PHP version(s): ${SORTED_VERSIONS[*]}"
echo

for version in "${SORTED_VERSIONS[@]}"; do
  echo "=== PHP ${version} ==="
  build_variant "$version" base    || true
  build_variant "$version" secure  || true
  build_variant "$version" advance || true
  echo
done

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
if [[ $FAILED -ne 0 ]]; then
  echo "One or more Docker builds failed." >&2
  exit 1
fi
echo "All Docker builds passed."
