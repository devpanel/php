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
#     base/Dockerfile               ← shared; stages: downloader + php-ext-common
#     {version}/base/Dockerfile     ← FROM common-php-ext AS final
#     secure/Dockerfile             ← shared; stages: secure-intermediate + final
#     {version}/secure/Dockerfile   ← per-version (7.4/8.0 only, multipart fix)
#     advance/Dockerfile            ← shared; FROM ${BASE_IMAGE}
#
# For the new structure, intermediate images are resolved in this order:
#   1. Pull from GHCR (fast path — requires auth and images to exist).
#   2. Build locally from base/Dockerfile (fallback — self-contained, slow
#      on first run but benefits from GitHub Actions cache on subsequent runs).
#
# Image references between stages use OCI layout directories (oci-layout://)
# rather than local Docker daemon tags.  This works with the docker-container
# buildx driver used in CI (which cannot see the host daemon's local images).
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
declare -A BUILD_VERSIONS   # key = version string, value = 1

if [[ -n "$TARGET_VERSION" ]]; then
  BUILD_VERSIONS["$TARGET_VERSION"]=1
elif [[ ${#EXTRA_FILES[@]} -gt 0 ]]; then
  # Mirror the Detect-versions logic from build-php-images.yml:
  # Changes to shared top-level directories (base/, secure/, advance/) or
  # docker-bake.hcl affect ALL versions; per-version paths only affect that
  # version.
  ALL_VERSIONS=false
  for f in "${EXTRA_FILES[@]}"; do
    # Shared top-level Dockerfile sources and docker-bake.hcl → rebuild all.
    if echo "$f" | grep -qE '(^|/)docker-bake\.hcl$|(^|/)(base|secure|advance)/'; then
      if ! echo "$f" | grep -qE '(^|/)[0-9]+\.[0-9]+/'; then
        ALL_VERSIONS=true
        break
      fi
    fi
  done
  if $ALL_VERSIONS; then
    for dir in "$REPO_ROOT"/*/base/Dockerfile; do
      version="$(basename "$(dirname "$(dirname "$dir")")")"
      BUILD_VERSIONS["$version"]=1
    done
  else
    for f in "${EXTRA_FILES[@]}"; do
      # Extract version from paths like .../8.2/base/Dockerfile
      version="$(echo "$f" | sed 's|.*[/]\([0-9][0-9]*\.[0-9][0-9]*\)[/].*|\1|' | grep -E '^[0-9]+\.[0-9]+$' || true)"
      if [[ -n "$version" ]]; then
        BUILD_VERSIONS["$version"]=1
      fi
    done
  fi
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
# GitHub Actions cache flag variable (no-op when not in CI)
# ---------------------------------------------------------------------------
IN_GHA="${ACTIONS_CACHE_URL:+1}"

# ---------------------------------------------------------------------------
# OCI working directory: all intermediate images are stored here as OCI
# layout directories.  Cleaned up on exit.
# ---------------------------------------------------------------------------
OCI_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/devpanel-php-build-XXXXXX")"
LOADED_TAGS=()   # local daemon images loaded by build_to_oci --tag (for run tests)
cleanup() {
  echo "Removing temporary build artifacts…"
  rm -rf "${OCI_WORK_DIR}"
  if [[ ${#LOADED_TAGS[@]} -gt 0 ]]; then
    echo "Removing local test images…"
    for tag in "${LOADED_TAGS[@]}"; do
      docker rmi --force "$tag" 2>/dev/null || true
    done
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Build helpers
# ---------------------------------------------------------------------------
FAILED=0

# build_to_oci <name> <context-dir> [extra docker buildx build args...]
#
# Builds an image and exports it as an OCI layout directory at
# ${OCI_WORK_DIR}/<name>.  Callers reference the result with:
#   --build-context foo=oci-layout://${OCI_WORK_DIR}/<name>
#
# The OCI layout approach works with the docker-container buildx driver: the
# Docker client reads the directory on the HOST and sends it to the builder,
# so no registry access is required for local intermediate images.
#
# If a --tag NAME:TAG argument is included among the extra args, the OCI tar
# is also fed to "docker load" so the image is available in the local daemon
# for functional (run) tests.  Docker 25+ can load OCI images; on older
# versions the load is silently skipped (run tests will then skip the variant).
build_to_oci() {
  local name="$1"
  local context="$2"
  shift 2

  # Scan for --tag to determine whether to also load into the daemon.
  local load_tag=""
  local i=0
  local -a forward_args=("$@")
  for (( i=0; i<${#forward_args[@]}; i++ )); do
    if [[ "${forward_args[$i]}" == "--tag" || "${forward_args[$i]}" == "-t" ]]; then
      if (( i+1 < ${#forward_args[@]} )); then
        load_tag="${forward_args[$((i+1))]}"
      fi
      break
    fi
  done

  local oci_tar="${OCI_WORK_DIR}/${name}.tar"
  local oci_dir="${OCI_WORK_DIR}/${name}"

  echo "  Building ${name}…"
  mkdir -p "${oci_dir}"
  if docker buildx build \
      --output "type=oci,dest=${oci_tar}" \
      "${forward_args[@]}" \
      "${context}" > /dev/null; then
    tar -xf "${oci_tar}" -C "${oci_dir}"

    # Optionally load into Docker daemon for run tests.
    # "docker load" can import OCI images since Docker 25; silently skipped
    # on older versions (run tests will then skip the variant with a warning).
    if [[ -n "$load_tag" ]]; then
      if docker load -i "${oci_tar}" 2>/dev/null; then
        LOADED_TAGS+=("$load_tag")
      else
        echo "  ▸ ${name} daemon load skipped (Docker <25 or load error; run tests may skip)" >&2
      fi
    fi

    rm -f "${oci_tar}"
    echo "  ✔ ${name} built successfully"
    return 0
  else
    rm -rf "${oci_dir}" "${oci_tar}"
    echo "  ✘ ${name} build FAILED" >&2
    FAILED=1
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Intermediate image helpers (new shared Dockerfile structure)
# ---------------------------------------------------------------------------

# Whether the downloader OCI has been produced this run.
DOWNLOADER_OCI_READY=0

# Ensure the version-independent 'downloader' OCI layout exists.
# Tries GHCR first (context will be docker-image://); falls back to building
# from base/Dockerfile and storing in OCI_WORK_DIR/downloader.
# Sets DOWNLOADER_CTX to the appropriate --build-context value.
DOWNLOADER_CTX=""
ensure_downloader_oci() {
  [[ "$DOWNLOADER_OCI_READY" -eq 1 ]] && return 0

  local ghcr_ref="${GHCR_REPO}:downloader${GHCR_TAG_SUFFIX}"

  # Fast path: pull from GHCR.  GHCR images are registry-resolvable from the
  # buildx container; no OCI export needed.
  if docker pull --quiet "${ghcr_ref}" 2>/dev/null; then
    echo "  ✔ downloader pulled from GHCR"
    DOWNLOADER_CTX="docker-image://${ghcr_ref}"
    DOWNLOADER_OCI_READY=1
    return 0
  fi

  echo "  downloader not in GHCR; building locally from base/Dockerfile…"
  local cache_args=()
  [[ -n "${IN_GHA}" ]] && cache_args=(
    --cache-from "type=gha,scope=php-ci-downloader"
    --cache-to   "type=gha,scope=php-ci-downloader,mode=max"
  )
  if ! build_to_oci "downloader" "${REPO_ROOT}/base" \
      --target downloader \
      "${cache_args[@]}"; then
    return 1
  fi
  DOWNLOADER_CTX="oci-layout://${OCI_WORK_DIR}/downloader"
  DOWNLOADER_OCI_READY=1
}

# Ensure the per-version 'php-ext-common' OCI layout exists.
# Sets PHP_EXT_CTX to the appropriate --build-context value.
PHP_EXT_CTX=""
ensure_php_ext_oci() {
  local version="$1"

  local ghcr_ref="${GHCR_REPO}:${version}-php-ext${GHCR_TAG_SUFFIX}"

  # Fast path: pull from GHCR.
  if docker pull --quiet "${ghcr_ref}" 2>/dev/null; then
    echo "  ✔ ${version}-php-ext pulled from GHCR"
    PHP_EXT_CTX="docker-image://${ghcr_ref}"
    return 0
  fi

  echo "  ${version}-php-ext not in GHCR; building locally from base/Dockerfile…"
  ensure_downloader_oci || return 1

  local cache_args=()
  [[ -n "${IN_GHA}" ]] && cache_args=(
    --cache-from "type=gha,scope=php-ci-ext-${version}"
    --cache-to   "type=gha,scope=php-ci-ext-${version},mode=max"
  )
  if ! build_to_oci "php-ext-${version}" "${REPO_ROOT}/base" \
      --target php-ext-common \
      --build-arg "PHP_VERSION=${version}" \
      --build-context "common-downloader=${DOWNLOADER_CTX}" \
      --build-context "common=${REPO_ROOT}/base" \
      "${cache_args[@]}"; then
    return 1
  fi
  PHP_EXT_CTX="oci-layout://${OCI_WORK_DIR}/php-ext-${version}"
}

# ---------------------------------------------------------------------------
# Per-version build
# ---------------------------------------------------------------------------
build_version() {
  local version="$1"
  local base_context="${REPO_ROOT}/${version}/base"
  local base_dockerfile="${base_context}/Dockerfile"

  # ── base ──────────────────────────────────────────────────────────────────
  if [[ ! -f "$base_dockerfile" ]]; then
    echo "  skip: ${version}/base/Dockerfile not found"
    return
  fi

  local base_extra_args=()

  # New structure: per-version base Dockerfile starts with "FROM common-php-ext".
  local base_df_content
  base_df_content="$(cat "$base_dockerfile")"
  if echo "$base_df_content" | grep -qE '^FROM common-php-ext'; then
    # Obtain the php-ext intermediate (GHCR or local OCI build).
    ensure_php_ext_oci "${version}" || return 1
    base_extra_args+=(--build-context "common-php-ext=${PHP_EXT_CTX}")

    # common-downloader context (if referenced by version-specific instructions)
    if echo "$base_df_content" | grep -qE '^(COPY|RUN)[[:space:]].*--from=common-downloader'; then
      ensure_downloader_oci || return 1
      base_extra_args+=(--build-context "common-downloader=${DOWNLOADER_CTX}")
    fi

    # Shared 'common' build context (./base/ directory).
    # Match '--from=common' only when not followed by a hyphen to avoid matching
    # '--from=common-downloader' or similar composed names.
    if echo "$base_df_content" | grep -qE '^(COPY|RUN)[[:space:]].*--from=common($|[^-])'; then
      base_extra_args+=(--build-context "common=${REPO_ROOT}/base")
    fi
  fi

  build_to_oci "${version}-base" "$base_context" \
      --tag "devpanel-php-test:${version}-base" \
      "${base_extra_args[@]}" || return 1

  # ── secure ────────────────────────────────────────────────────────────────
  # For FROM ${BASE_IMAGE}, pass --build-arg BASE_IMAGE=base-image (matches the
  # Dockerfile default) so Docker resolves the name via the --build-context below.
  # This avoids trying to pull a local tag from a remote registry.

  if [[ -f "${REPO_ROOT}/secure/Dockerfile" ]]; then
    # New shared secure/Dockerfile structure.
    # Build the 'final' target (which internally builds secure-intermediate on
    # top of the base image provided as the 'base-image' named context).
    if [[ -f "${REPO_ROOT}/${version}/secure/Dockerfile" ]]; then
      # Per-version secure Dockerfile (7.4/8.0 multipart fix): build
      # secure-intermediate first so it can be passed to the per-version file.
      build_to_oci "${version}-secure-int" "${REPO_ROOT}/secure" \
          --target secure-intermediate \
          --build-arg "BASE_IMAGE=base-image" \
          --build-context "base-image=oci-layout://${OCI_WORK_DIR}/${version}-base" \
          || return 1
      build_to_oci "${version}-secure" "${REPO_ROOT}/${version}/secure" \
          --tag "devpanel-php-test:${version}-secure" \
          --build-arg "BASE_IMAGE=base-image" \
          --build-context "base-image=oci-layout://${OCI_WORK_DIR}/${version}-secure-int" \
          || return 1
    else
      # Shared final stage (8.1+): single build up to 'final' target.
      build_to_oci "${version}-secure" "${REPO_ROOT}/secure" \
          --tag "devpanel-php-test:${version}-secure" \
          --target final \
          --build-arg "BASE_IMAGE=base-image" \
          --build-context "base-image=oci-layout://${OCI_WORK_DIR}/${version}-base" \
          || return 1
    fi
  elif [[ -f "${REPO_ROOT}/${version}/secure/Dockerfile" ]]; then
    # Legacy per-version standalone secure Dockerfile.
    build_to_oci "${version}-secure" "${REPO_ROOT}/${version}/secure" \
        --tag "devpanel-php-test:${version}-secure" \
        --build-arg "BASE_IMAGE=base-image" \
        --build-context "base-image=oci-layout://${OCI_WORK_DIR}/${version}-base" \
        || return 1
  else
    echo "  skip: secure Dockerfile not found for ${version}"
  fi

  # ── advance ───────────────────────────────────────────────────────────────
  local advance_context=""

  if [[ -f "${REPO_ROOT}/advance/Dockerfile" ]]; then
    advance_context="${REPO_ROOT}/advance"
  elif [[ -f "${REPO_ROOT}/${version}/advance/Dockerfile" ]]; then
    advance_context="${REPO_ROOT}/${version}/advance"
  fi

  if [[ -n "$advance_context" ]]; then
    build_to_oci "${version}-advance" "$advance_context" \
        --tag "devpanel-php-test:${version}-advance" \
        --build-arg "BASE_IMAGE=base-image" \
        --build-context "base-image=oci-layout://${OCI_WORK_DIR}/${version}-secure" \
        || return 1
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

