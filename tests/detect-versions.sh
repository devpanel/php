#!/usr/bin/env bash
# tests/detect-versions.sh — Detect which PHP versions are affected by changes.
#
# Single source of truth for version selection, shared by the local test
# scripts (tests/build-dockerfile.sh, tests/run-dockerfile.sh) and the CI
# detect job in .github/workflows/build-php-images.yml.
#
# Usage:
#   detect-versions.sh
#       Return all PHP versions found in the repository.
#
#   detect-versions.sh --files <path> [<path> ...]
#       Return PHP versions affected by the listed file paths.  Paths may be
#       absolute or relative to the repository root.
#
#   detect-versions.sh --before <sha> --after <sha>
#       Return PHP versions affected by files changed between the two commits.
#       On a brand-new branch (before SHA is all zeros) all versions are
#       returned.
#
# Optional flag (applies to all modes above):
#   --stage base|secure|advance   (default: advance)
#       Return only versions that need the given stage rebuilt.
#
#       Build order (and image dependency chain):
#           base → secure (built FROM base) → advance (built FROM secure)
#
#       A change to a lower stage forces all stages that depend on it to be
#       rebuilt.  Therefore each --stage value selects a different subset:
#
#         --stage base
#             Returns versions where base source changed.
#             Only a base change requires rebuilding base; changes to secure
#             or advance do not affect the base image.
#             Mirrors the workflow's 'versions_base' output.
#
#         --stage secure
#             Returns versions where secure or base source changed.
#             A base change requires rebuilding secure (secure is built FROM
#             base), so those versions are included too.
#             Mirrors the workflow's 'versions_secure' output.
#
#         --stage advance  (default)
#             Returns versions where advance, secure, or base source changed.
#             A secure or base change requires rebuilding advance (advance is
#             built FROM secure FROM base), so those versions are included too.
#             Mirrors the workflow's 'versions' output.
#
# Shared-directory rule (mirrors build-php-images.yml):
#   Changes to the top-level base/, secure/, or advance/ directories, or to
#   docker-bake.hcl, are treated as affecting ALL versions because those
#   sources are shared across every version's build.
#
# Output: one PHP version per line, sorted by version number.  Exits 0 in all
# non-error cases, including when no versions are affected (empty output).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
BEFORE=""
AFTER=""
EXTRA_FILES=()
STAGE="advance"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --before)
      if [[ $# -lt 2 || "$2" == --* ]]; then
        echo "Error: --before requires a SHA argument." >&2; exit 1
      fi
      BEFORE="$2"; shift 2 ;;
    --after)
      if [[ $# -lt 2 || "$2" == --* ]]; then
        echo "Error: --after requires a SHA argument." >&2; exit 1
      fi
      AFTER="$2"; shift 2 ;;
    --stage)
      if [[ $# -lt 2 || "$2" == --* ]]; then
        echo "Error: --stage requires base, secure, or advance." >&2; exit 1
      fi
      STAGE="$2"; shift 2 ;;
    --files)
      shift
      while [[ $# -gt 0 && "$1" != --* ]]; do
        EXTRA_FILES+=("$1"); shift
      done ;;
    *)
      echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ "$STAGE" != "base" && "$STAGE" != "secure" && "$STAGE" != "advance" ]]; then
  echo "Error: --stage must be base, secure, or advance (got: $STAGE)." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Output all PHP version directories in the repository, sorted by version.
all_versions() {
  find "$REPO_ROOT" -maxdepth 1 -mindepth 1 -type d -name '[0-9]*.[0-9]*' \
    | sed "s|$REPO_ROOT/||" | sort -V
}

# Normalize a file path to be relative to REPO_ROOT, without a leading "./"
normalize_path() {
  local p="$1"
  p="${p#./}"
  if [[ "$p" == "$REPO_ROOT/"* ]]; then
    p="${p#"$REPO_ROOT/"}"
  fi
  printf '%s' "$p"
}

# Return true (exit 0) when at least one entry in CHANGED_FILES has the given
# path prefix (relative to the repo root).
path_changed() {
  local prefix="$1" f norm
  for f in "${CHANGED_FILES[@]+"${CHANGED_FILES[@]}"}"; do
    norm="$(normalize_path "$f")"
    if [[ "$norm" == "$prefix"* ]]; then
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# Build the CHANGED_FILES list
# ---------------------------------------------------------------------------
declare -a CHANGED_FILES=()
ALL_VERSIONS=false

if [[ -n "$BEFORE" && -n "$AFTER" ]]; then
  # Git-diff mode.
  if [[ "$BEFORE" == "0000000000000000000000000000000000000000" ]]; then
    # Brand-new branch push — treat every version as affected.
    ALL_VERSIONS=true
  else
    while IFS= read -r f; do
      CHANGED_FILES+=("$f")
    done < <(cd "$REPO_ROOT" && git diff --name-only "$BEFORE" "$AFTER" 2>/dev/null)
  fi
elif [[ ${#EXTRA_FILES[@]} -gt 0 ]]; then
  CHANGED_FILES=("${EXTRA_FILES[@]}")
else
  # No filter specified: return all versions.
  all_versions
  exit 0
fi

# ---------------------------------------------------------------------------
# Detect whether any shared-directory change affects all versions
# ---------------------------------------------------------------------------
# Cascade mirrors build-php-images.yml:
#   docker-bake.hcl or base/ change → base, secure, and advance all affected
#   secure/ change                  → secure and advance affected
#   advance/ change                 → only advance affected
if ! $ALL_VERSIONS; then
  SHARED_NEEDS_BASE=false
  SHARED_NEEDS_SECURE=false
  SHARED_NEEDS_ADVANCE=false

  if path_changed "base/" || path_changed "docker-bake.hcl"; then
    SHARED_NEEDS_BASE=true; SHARED_NEEDS_SECURE=true; SHARED_NEEDS_ADVANCE=true
  fi
  if ! $SHARED_NEEDS_SECURE && path_changed "secure/"; then
    SHARED_NEEDS_SECURE=true; SHARED_NEEDS_ADVANCE=true
  fi
  if ! $SHARED_NEEDS_ADVANCE && path_changed "advance/"; then
    SHARED_NEEDS_ADVANCE=true
  fi

  # If the relevant shared stage is affected, every version needs that stage.
  case "$STAGE" in
    base)    if $SHARED_NEEDS_BASE;    then all_versions; exit 0; fi ;;
    secure)  if $SHARED_NEEDS_SECURE;  then all_versions; exit 0; fi ;;
    advance) if $SHARED_NEEDS_ADVANCE; then all_versions; exit 0; fi ;;
  esac
fi

if $ALL_VERSIONS; then
  all_versions
  exit 0
fi

# ---------------------------------------------------------------------------
# Per-version check
# ---------------------------------------------------------------------------
while IFS= read -r VER; do
  NEEDS_BASE=false
  NEEDS_SECURE=false
  NEEDS_ADVANCE=false

  if path_changed "${VER}/base/"; then
    NEEDS_BASE=true; NEEDS_SECURE=true; NEEDS_ADVANCE=true
  fi
  if ! $NEEDS_SECURE && path_changed "${VER}/secure/"; then
    NEEDS_SECURE=true; NEEDS_ADVANCE=true
  fi
  if ! $NEEDS_ADVANCE && path_changed "${VER}/advance/"; then
    NEEDS_ADVANCE=true
  fi

  case "$STAGE" in
    base)    if $NEEDS_BASE;    then echo "$VER"; fi ;;
    secure)  if $NEEDS_SECURE;  then echo "$VER"; fi ;;
    advance) if $NEEDS_ADVANCE; then echo "$VER"; fi ;;
  esac
done < <(all_versions)
