# docker-bake.hcl — Docker Buildx Bake file for devpanel/php
#
# Build graph (→ = "depends on"):
#   downloader             (GHCR stored + cached, not pushed to Docker Hub)
#     └─▶ phpX_Y-php-ext   (GHCR stored + cached, not pushed to Docker Hub)
#           └─▶ phpX_Y-base        (GHA cached, pushed to Docker Hub)
#                 └─▶ phpX_Y-secure-int  (GHCR stored + cached, not pushed to Docker Hub)
#                       └─▶ phpX_Y-secure    (GHA cached, pushed to Docker Hub)
#                             └─▶ phpX_Y-advance  (GHA cached, pushed to Docker Hub)
#
# Key variables (all overridable via environment variables):
#   REPO                          Docker Hub repository                        (devpanel/php)
#   GHCR_REPO                     GitHub Container Registry repository         (ghcr.io/devpanel/php)
#   TAG_SUFFIX                    Image tag suffix                             ("" on main, "-rc" on develop)
#   VERSIONS                      Space-separated PHP version dirs             ("7.4 8.0 8.1 8.2 8.3")
#   LATEST_PHP_VERSION            Highest PHP version dir in the repo          (8.3)
#   CODESERVER_VERSION            code-server version ("" = use Dockerfile default) ("")
#   COPILOT_CHAT_VERSION          Copilot Chat VSIX version ("" = use Dockerfile default) ("")
#   CORERULESET_VERSION           ModSecurity CRS version                      (3.3.5)
#   CACHE_FROM_ENABLED            Read from GHA/GHCR cache ("true"/"false")    ("true")
#   PLATFORMS                     Comma-separated target platforms             ("linux/amd64,linux/arm64")
#   PUSH_BY_DIGEST                When "true", push final images by digest     ("false")
#                                 without tags (used for per-platform CI jobs)
#   VERSIONS_NEEDING_MULTIPART_FIX  Versions running Debian 11 / modsec 2.9.3  ("7.4 8.0")
#
# Intermediate targets pushed to GHCR (never pushed to Docker Hub):
#   downloader, phpX_Y-php-ext, phpX_Y-secure-int
# These are permanently stored in the GitHub Container Registry and use
# type=registry cache (mode=max) for efficient incremental rebuilds.
# When PUSH_BY_DIGEST=true, final images are pushed to Docker Hub by content
# digest without tags.  The merge-manifests action combines the per-platform
# digests into the final multi-arch manifest tag.

# ─── Default group ───────────────────────────────────────────────────────────
# Running `docker buildx bake` without arguments builds this group.
# All three stage groups are listed explicitly: Docker Buildx Bake only pushes
# images that belong to a target listed in the group being built.  Targets that
# are used only as named build contexts (context dependencies) are built but
# never pushed, even when they carry tags.  Listing php-base and php-secure
# here ensures they are treated as first-class push targets.
# VERSIONS_BASE / VERSIONS_SECURE control which versions are tagged and pushed
# to Docker Hub for the base / secure stages respectively (via should_push()).
# Versions absent from those lists are still built (they are required by the
# advance dependency chain) but produce no Docker Hub tags and are not pushed.
# No per-version target names are passed as CLI arguments, which avoids the
# bake v0.31+ restriction on resolving matrix-generated names.
group "default" {
  targets = ["php-base", "php-secure", "php-advance"]
}

variable "REPO"                          { default = "devpanel/php"            }
# GHCR_REPO is overridden in CI via the GHCR_REPO env variable (see workflow files).
# The default below is a convenience fallback for local development only.
variable "GHCR_REPO"                     { default = "ghcr.io/devpanel/php"    }
variable "TAG_SUFFIX"                    { default = ""                        }
variable "VERSIONS"                      { default = "7.4 8.0 8.1 8.2 8.3"    }
# VERSIONS_BASE / VERSIONS_SECURE: subsets of VERSIONS for which the base /
# secure final images should be tagged and pushed to Docker Hub.  Both default
# to the full VERSIONS set so a plain `docker buildx bake` pushes everything.
# CI narrows these to only the versions whose files actually changed.
variable "VERSIONS_BASE"                 { default = "7.4 8.0 8.1 8.2 8.3"    }
variable "VERSIONS_SECURE"               { default = "7.4 8.0 8.1 8.2 8.3"    }
variable "LATEST_PHP_VERSION"            { default = "8.3"                     }
variable "CODESERVER_VERSION"            { default = ""                                                     }
variable "CODESERVER_DEB_SHA256_AMD64"   { default = ""                                                     }
variable "CODESERVER_DEB_SHA256_ARM64"   { default = ""                                                     }
variable "COPILOT_CHAT_VERSION"          { default = ""                                                     }
variable "COPILOT_CHAT_VSIX_SHA256"      { default = ""                                                     }
variable "CORERULESET_VERSION"           { default = "3.3.5"                   }
# DOWNLOADS_DIR: path to a directory whose pre-downloaded/ subdirectory contains
# pre-seeded build artifacts (code-server .deb files and Copilot Chat VSIX).
# When set by CI to a runner-local path pre-populated by actions/cache@v5, the
# downloader stage bind-mounts /pre-downloaded from it instead of downloading.
# When empty (default), no named context override is provided and the Dockerfile's
# 'downloads' stage (FROM alpine:3 with an empty /pre-downloaded dir) is used,
# causing all downloads to fall through to the normal network path.
variable "DOWNLOADS_DIR"                 { default = ""                        }
variable "CACHE_FROM_ENABLED"            { default = "true"                    }
# GHCR_WRITABLE is set by the "Check GHCR write access" workflow step.
# "true"  → GHCR cache writes proceed without ignore-error: any failure is a
#            real error that will fail the build (write was expected to succeed).
# "false" → GHCR cache writes use ignore-error=true: failures surface in the
#            log but do not abort the build (write was not expected to succeed).
# Default is "false" so that local dev builds (where no pre-flight check runs)
# never abort due to a GHCR write failure.
variable "GHCR_WRITABLE"                { default = "false"                   }
variable "PLATFORMS"                     { default = "linux/amd64,linux/arm64" }
# PUSH_BY_DIGEST: when "true", final images (base/secure/advance) are pushed
# to Docker Hub by content digest without creating any tags.  The
# merge-manifests action then creates the final multi-arch manifest tag by
# combining the per-platform digests received from both build jobs.  Used by
# CI per-platform builds (one job per platform) so the final tag is assembled
# from all digests without ever creating platform-specific tags.
variable "PUSH_BY_DIGEST"               { default = "false"                   }
# Versions using Debian 11 / mod_security 2.9.3 that require the
# REQUEST-922-MULTIPART-ATTACK rule to be removed.
variable "VERSIONS_NEEDING_MULTIPART_FIX" { default = "7.4 8.0" }

# ─── Cache helpers ────────────────────────────────────────────────────────────
# cache_from: read from GHA cache (push workflow only; full-rebuild sets CACHE_FROM_ENABLED=false)
# cache_to:   always write to GHA cache (mode=max caches all intermediate layers)

# ver_key: converts a version string ("8.1") to a key safe for target names ("8_1").
# Dots are not valid in HCL identifiers (they are the attribute-access operator),
# so they must be replaced. Underscores are used rather than simply removing the
# dot to avoid ambiguity when major versions reach two digits
# (e.g. "10.1" → "10_1" is distinct from a hypothetical "1.01" → "1_01").
function "ver_key" {
  params = [v]
  result = replace(v, ".", "_")
}

# should_push: true if version v is listed in the space-separated stage_versions
# string.  Used to make Docker Hub tags conditional: targets whose version is not
# in the per-stage list are still built (for the dependency chain / GHCR cache)
# but are not tagged and therefore not pushed to Docker Hub.
function "should_push" {
  params = [stage_versions, v]
  result = contains(split(" ", trimspace(stage_versions)), v)
}

function "cache_from" {
  params = [scope]
  result = CACHE_FROM_ENABLED == "true" ? ["type=gha,scope=${scope}"] : []
}

function "cache_to" {
  params = [scope]
  result = ["type=gha,scope=${scope},mode=max"]
}

# cache_from_registry / cache_to_registry: registry-based cache in GHCR with
# GHA cache as a fallback.  Used for intermediate targets (downloader, php-ext,
# secure-int) so their build layers survive beyond the GHA cache eviction window.
# cache_to_registry behaviour depends on GHCR_WRITABLE (set by the workflow's
# "Check GHCR write access" pre-flight step):
#   "true"  → write without ignore-error: a failure is unexpected and should
#              fail the build so the operator is forced to investigate.
#   "false" → write with ignore-error=true: the pre-flight check already warned
#              that GHCR is unwritable; errors are still visible in the bake log
#              but must not abort a build that would otherwise succeed.
#
# Cross-branch cache sharing:
#   actions/cache entries are scoped to the current branch + its base branches
#   + the default branch, so sibling branches cannot share each other's
#   actions/cache entries.  The GHCR registry cache is not subject to that
#   restriction: any branch with pull access to GHCR can read any tag.
#   cache_from_registry therefore always reads from the branch-specific ref
#   (the primary source) and, when TAG_SUFFIX is non-empty (i.e. not on main),
#   also reads from main's cache ref (the same ref with TAG_SUFFIX stripped).
#   This means any intermediate layer that was previously built and cached by
#   a main-branch CI run is immediately reusable on any other branch, even for
#   sibling branches that cannot access each other's actions/cache entries.
#
# main_cache_ref: strips TAG_SUFFIX from the image tag portion of a GHCR ref,
# yielding the main-branch equivalent ref.  A greedy regex extracts everything
# up to the last ":" as the registry+path component and everything after as the
# tag, so refs with a port in the hostname (e.g. localhost:5000/repo:tag) are
# handled correctly.  The TAG_SUFFIX is appended once by the detect step, so a
# plain replace on the tag portion always removes exactly one occurrence.

function "main_cache_ref" {
  params = [ref]
  # Strips TAG_SUFFIX from only the tag portion of ref (everything after the
  # last ":"), keeping the registry/path portion unchanged even if it happens
  # to contain the same string.  HCL functions have no local variables, so
  # regex() is evaluated twice; the identical calls are intentional.
  result = join(":", [
    regex("^(.+):([^:]+)$", ref)[0],
    replace(regex("^(.+):([^:]+)$", ref)[1], TAG_SUFFIX, "")
  ])
}

function "cache_from_registry" {
  params = [ref, scope]
  result = CACHE_FROM_ENABLED == "true" ? concat(
    ["type=registry,ref=${ref}"],
    TAG_SUFFIX != "" ? ["type=registry,ref=${main_cache_ref(ref)}"] : [],
    cache_from(scope)
  ) : []
}

function "cache_to_registry" {
  params = [ref, scope]
  result = GHCR_WRITABLE == "true" ? concat(["type=registry,ref=${ref},mode=max"], cache_to(scope)) : concat(["type=registry,ref=${ref},mode=max,ignore-error=true"], cache_to(scope))
}

# ─── Shared downloader (pushed to GHCR, NOT pushed to Docker Hub) ────────────
# Downloads code-server .deb and libsodium source; both are version-independent.
# Referenced by every phpX_Y-php-ext target via the 'common-downloader'
# named context.
target "downloader" {
  dockerfile = "Dockerfile"
  context    = "base"
  target     = "downloader"
  platforms  = split(",", PLATFORMS)
  # When DOWNLOADS_DIR is set, override the 'downloads' named context with that
  # directory so Docker uses pre-seeded files instead of downloading from the
  # internet.  When empty (default), no override is provided and the Dockerfile's
  # 'downloads' stage (FROM alpine:3 with an empty /pre-downloaded dir) is used,
  # causing all downloads to fall through to the normal network path.
  contexts = DOWNLOADS_DIR != "" ? { downloads = DOWNLOADS_DIR } : {}
  args = merge(
    { LATEST_PHP_VERSION = LATEST_PHP_VERSION },
    CODESERVER_VERSION          != "" ? { CODESERVER_VERSION          = CODESERVER_VERSION          } : {},
    CODESERVER_DEB_SHA256_AMD64 != "" ? { CODESERVER_DEB_SHA256_AMD64 = CODESERVER_DEB_SHA256_AMD64 } : {},
    CODESERVER_DEB_SHA256_ARM64 != "" ? { CODESERVER_DEB_SHA256_ARM64 = CODESERVER_DEB_SHA256_ARM64 } : {},
    COPILOT_CHAT_VERSION        != "" ? { COPILOT_CHAT_VERSION        = COPILOT_CHAT_VERSION        } : {},
    COPILOT_CHAT_VSIX_SHA256    != "" ? { COPILOT_CHAT_VSIX_SHA256    = COPILOT_CHAT_VSIX_SHA256    } : {}
  )
  tags       = ["${GHCR_REPO}:downloader${TAG_SUFFIX}"]
  cache-from = cache_from_registry("${GHCR_REPO}:cache-downloader${TAG_SUFFIX}", "downloader")
  cache-to   = cache_to_registry("${GHCR_REPO}:cache-downloader${TAG_SUFFIX}", "downloader")
}

# ─── Common php-ext intermediates (pushed to GHCR, NOT pushed to Docker Hub) ─
# Builds the php-ext-common stage from base/Dockerfile for each PHP version.
# Contains all extensions, packages, and tools common to every version.
# Version-specific differences (avif, pcre, gd flags, imagick method, etc.)
# are in each {version}/base/Dockerfile.
#
# Matrix generates one target per version: php7_4-php-ext, php8_0-php-ext, ...

target "_php-ext-common" {
  dockerfile = "Dockerfile"
  target     = "php-ext-common"
  context    = "base"
  contexts = {
    common-downloader = "target:downloader"
    common            = "./base"
  }
  platforms  = split(",", PLATFORMS)
  # No tags → not pushed to Docker Hub
}

target "php-php-ext" {
  matrix = {
    version = split(" ", trimspace(VERSIONS))
  }
  name     = "php${ver_key(version)}-php-ext"
  inherits = ["_php-ext-common"]
  args     = { PHP_VERSION = version }
  tags       = ["${GHCR_REPO}:${version}-php-ext${TAG_SUFFIX}"]
  cache-from = cache_from_registry("${GHCR_REPO}:cache-${version}-php-ext${TAG_SUFFIX}", "php${ver_key(version)}-php-ext")
  cache-to   = cache_to_registry("${GHCR_REPO}:cache-${version}-php-ext${TAG_SUFFIX}", "php${ver_key(version)}-php-ext")
}

# ─── Base final images ────────────────────────────────────────────────────────
# Each version has its own Dockerfile containing only version-specific
# differences (gd/avif, pcre, PECL extensions, tool version overrides).
# 'common-php-ext' provides the shared php-ext intermediate without a registry
# push.  'common-downloader' provides code-server .deb.  'common' exposes
# ./base/ for any remaining shared assets.

target "_base-common" {
  platforms  = split(",", PLATFORMS)
}

target "php-base" {
  matrix = {
    version = split(" ", trimspace(VERSIONS))
  }
  name       = "php${ver_key(version)}-base"
  inherits   = ["_base-common"]
  dockerfile = "Dockerfile"
  context    = "${version}/base"
  contexts = {
    common-php-ext    = "target:php${ver_key(version)}-php-ext"
    common-downloader = "target:downloader"
    common            = "./base"
  }
  tags       = PUSH_BY_DIGEST == "true" ? [] : (should_push(VERSIONS_BASE, version) ? ["${REPO}:${version}-base${TAG_SUFFIX}"] : [])
  output     = PUSH_BY_DIGEST == "true" && should_push(VERSIONS_BASE, version) ? ["type=image,name=${REPO},push-by-digest=true,name-canonical=true,push=true"] : []
  cache-from = cache_from("php${ver_key(version)}-base")
  cache-to   = cache_to("php${ver_key(version)}-base")
}

# ─── Secure intermediate targets (pushed to GHCR, NOT pushed to Docker Hub) ──
# Built from the secure-intermediate stage of secure/Dockerfile on top of each
# version's base image.

target "_secure-int-common" {
  dockerfile = "Dockerfile"
  target     = "secure-intermediate"
  context    = "secure"
  platforms  = split(",", PLATFORMS)
  args       = { BASE_IMAGE = "base-image", CORERULESET_VERSION = CORERULESET_VERSION }
  # No tags → not pushed to Docker Hub
}

target "php-secure-int" {
  matrix = {
    version = split(" ", trimspace(VERSIONS))
  }
  name     = "php${ver_key(version)}-secure-int"
  inherits = ["_secure-int-common"]
  contexts = { base-image = "target:php${ver_key(version)}-base" }
  tags       = ["${GHCR_REPO}:${version}-secure-int${TAG_SUFFIX}"]
  cache-from = cache_from_registry("${GHCR_REPO}:cache-${version}-secure-int${TAG_SUFFIX}", "php${ver_key(version)}-secure-int")
  cache-to   = cache_to_registry("${GHCR_REPO}:cache-${version}-secure-int${TAG_SUFFIX}", "php${ver_key(version)}-secure-int")
}

# ─── Secure final images ──────────────────────────────────────────────────────
# Versions in VERSIONS_NEEDING_MULTIPART_FIX (7.4 and 8.0) use a per-version
# Dockerfile to remove the REQUEST-922-MULTIPART-ATTACK rule (mod_security 2.9.3
# on Debian 11 doesn't support it).  All other versions use the shared 'final'
# stage from secure/Dockerfile, which just inherits USER/WORKDIR/CMD from the
# secure-intermediate without adding new layers.

target "_secure-common" {
  platforms  = split(",", PLATFORMS)
  args       = { BASE_IMAGE = "secure-intermediate" }
  target     = "final"
}

target "php-secure" {
  matrix = {
    version = split(" ", trimspace(VERSIONS))
  }
  name       = "php${ver_key(version)}-secure"
  inherits   = ["_secure-common"]
  dockerfile = "Dockerfile"
  context    = contains(split(" ", VERSIONS_NEEDING_MULTIPART_FIX), version) ? "${version}/secure" : "secure"
  contexts   = { secure-intermediate = "target:php${ver_key(version)}-secure-int" }
  tags       = PUSH_BY_DIGEST == "true" ? [] : (should_push(VERSIONS_SECURE, version) ? ["${REPO}:${version}-secure${TAG_SUFFIX}"] : [])
  output     = PUSH_BY_DIGEST == "true" && should_push(VERSIONS_SECURE, version) ? ["type=image,name=${REPO},push-by-digest=true,name-canonical=true,push=true"] : []
  cache-from = cache_from("php${ver_key(version)}-secure")
  cache-to   = cache_to("php${ver_key(version)}-secure")
}

# ─── Advance final images ─────────────────────────────────────────────────────
# All versions use the same advance/Dockerfile; only the base image differs.

target "_advance-common" {
  dockerfile = "Dockerfile"
  context    = "advance"
  platforms  = split(",", PLATFORMS)
  args       = { BASE_IMAGE = "base-image" }
}

target "php-advance" {
  matrix = {
    version = split(" ", trimspace(VERSIONS))
  }
  name     = "php${ver_key(version)}-advance"
  inherits = ["_advance-common"]
  contexts = { base-image = "target:php${ver_key(version)}-secure" }
  tags     = PUSH_BY_DIGEST == "true" ? [] : ["${REPO}:${version}-advance${TAG_SUFFIX}"]
  output   = PUSH_BY_DIGEST == "true" ? ["type=image,name=${REPO},push-by-digest=true,name-canonical=true,push=true"] : []
  cache-from = cache_from("php${ver_key(version)}-advance")
  cache-to   = cache_to("php${ver_key(version)}-advance")
}
