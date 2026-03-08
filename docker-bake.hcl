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
#   REPO                          Docker Hub repository                   (devpanel/php)
#   GHCR_REPO                     GitHub Container Registry repository    (ghcr.io/devpanel/php)
#   TAG_SUFFIX                    Image tag suffix                        ("" on main, "-rc" on develop)
#   VERSIONS                      Space-separated PHP version dirs        ("7.4 8.0 8.1 8.2 8.3")
#   LATEST_PHP_VERSION            Highest PHP version dir in the repo     (8.3)
#   CODESERVER_VERSION            code-server version to pin ("" = auto)  ("")
#   CORERULESET_VERSION           ModSecurity CRS version                 (3.3.5)
#   CACHE_FROM_ENABLED            Read from GHA/GHCR cache ("true"/"false")  ("true")
#   PLATFORMS                     Comma-separated target platforms        ("linux/amd64,linux/arm64")
#   VERSIONS_NEEDING_MULTIPART_FIX  Versions running Debian 11 / modsec 2.9.3  ("7.4 8.0")
#
# Intermediate targets pushed to GHCR (never pushed to Docker Hub):
#   downloader, phpX_Y-php-ext, phpX_Y-secure-int
# These are permanently stored in the GitHub Container Registry and use
# type=registry cache (mode=max) for efficient incremental rebuilds.

# ─── Default group ───────────────────────────────────────────────────────────
# Running `docker buildx bake` without arguments builds this group.
# php-advance depends on the full chain, so every tagged image is built and
# pushed automatically; no explicit target list is needed in CI.
group "default" {
  targets = ["php-advance"]
}

variable "REPO"                          { default = "devpanel/php"            }
# GHCR_REPO is overridden in CI via the GHCR_REPO env variable (see workflow files).
# The default below is a convenience fallback for local development only.
variable "GHCR_REPO"                     { default = "ghcr.io/devpanel/php"    }
variable "TAG_SUFFIX"                    { default = ""                        }
variable "VERSIONS"                      { default = "7.4 8.0 8.1 8.2 8.3"     }
variable "LATEST_PHP_VERSION"            { default = "8.3"                     }
variable "CODESERVER_VERSION"            { default = ""                        }
variable "CORERULESET_VERSION"           { default = "3.3.5"                   }
variable "CACHE_FROM_ENABLED"            { default = "true"                    }
variable "PLATFORMS"                     { default = "linux/amd64,linux/arm64" }
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

function "cache_from" {
  params = [scope]
  result = CACHE_FROM_ENABLED == "true" ? ["type=gha,scope=${scope}"] : []
}

function "cache_to" {
  params = [scope]
  result = ["type=gha,scope=${scope},mode=max"]
}

# cache_from_registry / cache_to_registry: permanent registry-based cache in GHCR.
# Used for intermediate targets (downloader, php-ext, secure-int) so that their
# build layers survive beyond the GHA cache eviction window.

function "cache_from_registry" {
  params = [ref]
  result = CACHE_FROM_ENABLED == "true" ? ["type=registry,ref=${ref}"] : []
}

function "cache_to_registry" {
  params = [ref]
  result = ["type=registry,ref=${ref},mode=max"]
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
  args = {
    LATEST_PHP_VERSION = LATEST_PHP_VERSION
    CODESERVER_VERSION = CODESERVER_VERSION
  }
  secret     = ["id=github_token,env=GITHUB_TOKEN"]
  tags       = ["${GHCR_REPO}:downloader${TAG_SUFFIX}"]
  cache-from = cache_from_registry("${GHCR_REPO}:cache-downloader${TAG_SUFFIX}")
  cache-to   = cache_to_registry("${GHCR_REPO}:cache-downloader${TAG_SUFFIX}")
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
  cache-from = cache_from_registry("${GHCR_REPO}:cache-${version}-php-ext${TAG_SUFFIX}")
  cache-to   = cache_to_registry("${GHCR_REPO}:cache-${version}-php-ext${TAG_SUFFIX}")
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
  tags       = ["${REPO}:${version}-base${TAG_SUFFIX}"]
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
  cache-from = cache_from_registry("${GHCR_REPO}:cache-${version}-secure-int${TAG_SUFFIX}")
  cache-to   = cache_to_registry("${GHCR_REPO}:cache-${version}-secure-int${TAG_SUFFIX}")
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
  tags       = ["${REPO}:${version}-secure${TAG_SUFFIX}"]
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
  tags     = ["${REPO}:${version}-advance${TAG_SUFFIX}"]
  cache-from = cache_from("php${ver_key(version)}-advance")
  cache-to   = cache_to("php${ver_key(version)}-advance")
}
