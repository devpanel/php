#!/usr/bin/env bash
# tests/build-dockerfile.sh — Build Docker images to verify they build
# successfully.  Does NOT push any images.
#
# Supports two Dockerfile structures:
#
#   Legacy (per-version standalone Dockerfiles):
#     {version}/base/Dockerfile     ← FROM php:<version>-apache
#     {version}/secure/Dockerfile   ← FROM devpanel/php:<version>-base
#     {version}/advance/Dockerfile  ← FROM devpanel/php:<version>-secure
#
#   New (shared base with GHCR-cached intermediates):
#     {version}/base/Dockerfile     ← FROM common-php-ext AS final
#     secure/Dockerfile             ← shared; stages: secure-intermediate + final
#     {version}/secure/Dockerfile   ← per-version (7.4/8.0 only, multipart fix)
#     advance/Dockerfile            ← shared; FROM ${BASE_IMAGE}
#
# The new structure requires GHCR auth to pull the common-php-ext and
# common-downloader intermediate images.
#
# This script builds base first, tags it locally, then builds secure using
# the locally-built base, and finally builds advance using locally-built
# secure.  All test tags are cleaned up on exit.
#
# Environment variables (override as needed):
#   GHCR_REPO         GHCR repository for intermediate images
#                     (default: ghcr.io/devpanel/php)
#   GHCR_TAG_SUFFIX   Tag suffix for GHCR intermediates; -rc on develop, empty
#                     on main (default: -rc)
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

# GHCR coordinates for pulling intermediate images in the new structure.
GHCR_REPO="${GHCR_REPO:-ghcr.io/devpanel/php}"
GHCR_TAG_SUFFIX="${GHCR_TAG_SUFFIX:--rc}"

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
    version="$(echo "$f" | sed 's|.*[/]\([0-9][0-9]*\.[0-9][0-9]*\)[/].*|\1|' | grep -E '^[0-9]+\.[0-9]+$' || true)"
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

# run_build <tag> <context-dir> [extra docker buildx build args...]
run_build() {
  local tag="$1"
  local context="$2"
  local prefix="${TAG_PREFIX}:"
  local name="${tag#"$prefix"}"
  shift 2
  echo "  Building ${name}…"
  if docker buildx build \
      --load \
      --quiet \
      "$@" \
      --tag "$tag" \
      "$context" > /dev/null; then
    CREATED_TAGS+=("$tag")
    echo "  ✔ ${name} built successfully"
    return 0
  else
    echo "  ✘ ${name} build FAILED" >&2
    FAILED=1
    return 1
  fi
}

build_version() {
  local version="$1"
  local base_context="${REPO_ROOT}/${version}/base"
  local base_dockerfile="${base_context}/Dockerfile"

  # ── base ──────────────────────────────────────────────────────────────────
  if [[ ! -f "$base_dockerfile" ]]; then
    echo "  skip: ${version}/base/Dockerfile not found"
    return
  fi

  local base_tag="${TAG_PREFIX}:${version}-base"
  local base_extra_args=()

  # New structure: per-version base Dockerfile starts with "FROM common-php-ext"
  # and requires the intermediate to be pulled from GHCR.
  # Read the Dockerfile once and check all named-context patterns together.
  local base_df_content
  base_df_content="$(cat "$base_dockerfile")"
  if echo "$base_df_content" | grep -qE '^FROM common-php-ext'; then
    local php_ext_ref="${GHCR_REPO}:${version}-php-ext${GHCR_TAG_SUFFIX}"
    base_extra_args+=(--build-context "common-php-ext=docker-image://${php_ext_ref}")
    # Also provide common-downloader context if referenced in a COPY --from= or RUN --mount=
    if echo "$base_df_content" | grep -qE '^(COPY|RUN)[[:space:]].*--from=common-downloader'; then
      local downloader_ref="${GHCR_REPO}:downloader${GHCR_TAG_SUFFIX}"
      base_extra_args+=(--build-context "common-downloader=docker-image://${downloader_ref}")
    fi
    # Provide the shared 'common' build context (./base/) if referenced.
    # Match '--from=common' only when not followed by a hyphen (to avoid matching
    # '--from=common-downloader' or similar composed names).
    if echo "$base_df_content" | grep -qE '^(COPY|RUN)[[:space:]].*--from=common($|[^-])'; then
      base_extra_args+=(--build-context "common=${REPO_ROOT}/base")
    fi
  fi

  run_build "$base_tag" "$base_context" "${base_extra_args[@]+"${base_extra_args[@]}"}" || return 1

  # ── secure ────────────────────────────────────────────────────────────────
  local secure_tag="${TAG_PREFIX}:${version}-secure"
  local secure_int_tag="${TAG_PREFIX}:${version}-secure-int"

  if [[ -f "${REPO_ROOT}/secure/Dockerfile" ]]; then
    # New shared secure/Dockerfile structure: has secure-intermediate + final stages.
    # Step 1: build the secure-intermediate stage (installs mod_security).
    run_build "$secure_int_tag" "${REPO_ROOT}/secure" \
        --target secure-intermediate \
        --build-arg "BASE_IMAGE=${base_tag}" || return 1

    # Step 2a: per-version final (7.4/8.0 multipart fix uses own Dockerfile).
    if [[ -f "${REPO_ROOT}/${version}/secure/Dockerfile" ]]; then
      run_build "$secure_tag" "${REPO_ROOT}/${version}/secure" \
          --build-arg "BASE_IMAGE=${secure_int_tag}" || return 1
    else
      # Step 2b: shared final stage — just retags secure-intermediate.
      run_build "$secure_tag" "${REPO_ROOT}/secure" \
          --target final \
          --build-arg "BASE_IMAGE=${base_tag}" || return 1
    fi
  elif [[ -f "${REPO_ROOT}/${version}/secure/Dockerfile" ]]; then
    # Legacy per-version standalone secure Dockerfile.
    run_build "$secure_tag" "${REPO_ROOT}/${version}/secure" \
        --build-arg "BASE_IMAGE=${base_tag}" || return 1
  else
    echo "  skip: secure Dockerfile not found for ${version}"
  fi

  # ── advance ───────────────────────────────────────────────────────────────
  local advance_tag="${TAG_PREFIX}:${version}-advance"
  local advance_context=""

  if [[ -f "${REPO_ROOT}/advance/Dockerfile" ]]; then
    advance_context="${REPO_ROOT}/advance"
  elif [[ -f "${REPO_ROOT}/${version}/advance/Dockerfile" ]]; then
    advance_context="${REPO_ROOT}/${version}/advance"
  fi

  if [[ -n "$advance_context" ]]; then
    run_build "$advance_tag" "$advance_context" \
        --build-arg "BASE_IMAGE=${secure_tag}" || return 1
  else
    echo "  skip: advance Dockerfile not found for ${version}"
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
  build_version "$version" || true
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

