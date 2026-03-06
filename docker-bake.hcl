# docker-bake.hcl — Docker Buildx Bake file for devpanel/php
#
# Build graph (→ = "depends on"):
#   downloader             (GHA cached, not pushed)
#     └─▶ phpX_Y-php-ext   (GHA cached, not pushed)
#           └─▶ phpX_Y-base        (GHA cached, pushed)
#                 └─▶ phpX_Y-secure-int  (GHA cached, not pushed)
#                       └─▶ phpX_Y-secure    (GHA cached, pushed)
#                             └─▶ phpX_Y-advance  (GHA cached, pushed)
#
# Key variables (all overridable via environment variables):
#   REPO                          Docker Hub repository                   (devpanel/php)
#   TAG_SUFFIX                    Image tag suffix                        ("" on main/develop)
#   VERSIONS                      Space-separated PHP version dirs        ("7.4 8.0 8.1 8.2 8.3")
#   LATEST_PHP_VERSION            Highest PHP version dir in the repo     (8.3)
#   CODESERVER_VERSION            code-server version to pin ("" = auto)  ("")
#   CORERULESET_VERSION           ModSecurity CRS version                 (3.3.5)
#   CACHE_FROM_ENABLED            Read from GHA cache ("true"/"false")    ("true")
#   PLATFORMS                     Comma-separated target platforms        ("linux/amd64,linux/arm64")
#   VERSIONS_NEEDING_MULTIPART_FIX  Versions running Debian 11 / modsec 2.9.3  ("7.4 8.0")
#
# Targets that are never pushed to Docker Hub:
#   downloader, phpX_Y-php-ext, phpX_Y-secure-int
# All of these are still cached in GitHub Actions (type=gha, mode=max).

variable "REPO"                          { default = "devpanel/php"          }
variable "TAG_SUFFIX"                    { default = ""                       }
variable "VERSIONS"                      { default = "7.4 8.0 8.1 8.2 8.3"   }
variable "LATEST_PHP_VERSION"            { default = "8.3"                    }
variable "CODESERVER_VERSION"            { default = ""                       }
variable "CORERULESET_VERSION"           { default = "3.3.5"                  }
variable "CACHE_FROM_ENABLED"            { default = "true"                   }
variable "PLATFORMS"                     { default = "linux/amd64,linux/arm64" }
# Versions using Debian 11 / mod_security 2.9.3 that require the
# REQUEST-922-MULTIPART-ATTACK rule to be removed.
variable "VERSIONS_NEEDING_MULTIPART_FIX" { default = "7.4 8.0" }

# ─── Cache helpers ────────────────────────────────────────────────────────────
# cache_from: read from GHA cache (push workflow only; full-rebuild sets CACHE_FROM_ENABLED=false)
# cache_to:   always write to GHA cache (mode=max caches all intermediate layers)

# ver_key: converts a version string ("8.1") to a key safe for target names ("8_1").
# Dots are replaced with underscores to avoid ambiguity when major versions
# reach two digits (e.g. "10.1" → "10_1" vs "1.01" → "1_01").
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

# ─── Shared downloader (NOT pushed, cached in GHA) ───────────────────────────
# Downloads code-server .deb and libsodium source; both are version-independent.
# Referenced by every phpX_Y-php-ext target via the 'common-downloader'
# named context.
target "downloader" {
  dockerfile = "base/Dockerfile"
  context    = "base"
  target     = "downloader"
  platforms  = split(",", PLATFORMS)
  args = {
    LATEST_PHP_VERSION = LATEST_PHP_VERSION
    CODESERVER_VERSION = CODESERVER_VERSION
  }
  secret     = ["id=github_token"]
  cache-from = cache_from("downloader")
  cache-to   = cache_to("downloader")
  # No tags → not pushed to Docker Hub
}

# ─── Common php-ext intermediates (NOT pushed, cached in GHA) ────────────────
# Builds the php-ext-common stage from base/Dockerfile for each PHP version.
# Contains all extensions, packages, and tools common to every version.
# Version-specific differences (avif, pcre, gd flags, imagick method, etc.)
# are in each {version}/base/Dockerfile.
#
# Matrix generates one target per version: php7_4-php-ext, php8_0-php-ext, ...

target "_php-ext-common" {
  dockerfile = "base/Dockerfile"
  target     = "php-ext-common"
  context    = "base"
  contexts = {
    common-downloader = "target:downloader"
    common            = "./base"
  }
  platforms  = split(",", PLATFORMS)
  secret     = ["id=github_token"]
  # No tags → not pushed to Docker Hub
}

target "php-php-ext" {
  matrix = {
    version = split(" ", trimspace(VERSIONS))
  }
  name     = "php${ver_key(version)}-php-ext"
  inherits = ["_php-ext-common"]
  args     = { PHP_VERSION = version }
  cache-from = cache_from("php${ver_key(version)}-php-ext")
  cache-to   = cache_to("php${ver_key(version)}-php-ext")
}

# ─── Base final images ────────────────────────────────────────────────────────
# Each version has its own Dockerfile containing only version-specific
# differences (gd/avif, pcre, PECL extensions, tool version overrides).
# 'common-php-ext' provides the shared php-ext intermediate without a registry
# push.  'common-downloader' provides code-server .deb.  'common' exposes
# ./base/ for any remaining shared assets.

target "_base-common" {
  platforms  = split(",", PLATFORMS)
  secret     = ["id=github_token"]
}

target "php-base" {
  matrix = {
    version = split(" ", trimspace(VERSIONS))
  }
  name       = "php${ver_key(version)}-base"
  inherits   = ["_base-common"]
  dockerfile = "${version}/base/Dockerfile"
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

# ─── Secure intermediate targets (NOT pushed, cached in GHA) ─────────────────
# Built from the secure-intermediate stage of secure/Dockerfile on top of each
# version's base image.

target "_secure-int-common" {
  dockerfile = "secure/Dockerfile"
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
  cache-from = cache_from("php${ver_key(version)}-secure-int")
  cache-to   = cache_to("php${ver_key(version)}-secure-int")
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
  dockerfile = contains(split(" ", VERSIONS_NEEDING_MULTIPART_FIX), version) ? "${version}/secure/Dockerfile" : "secure/Dockerfile"
  context    = contains(split(" ", VERSIONS_NEEDING_MULTIPART_FIX), version) ? "${version}/secure" : "secure"
  contexts   = { secure-intermediate = "target:php${ver_key(version)}-secure-int" }
  tags       = ["${REPO}:${version}-secure${TAG_SUFFIX}"]
  cache-from = cache_from("php${ver_key(version)}-secure")
  cache-to   = cache_to("php${ver_key(version)}-secure")
}

# ─── Advance final images ─────────────────────────────────────────────────────
# All versions use the same advance/Dockerfile; only the base image differs.

target "_advance-common" {
  dockerfile = "advance/Dockerfile"
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
