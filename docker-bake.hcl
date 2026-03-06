# docker-bake.hcl — Docker Buildx Bake file for devpanel/php
#
# Build graph (→ = "depends on"):
#   downloader           (GHA cached, not pushed)
#     └─▶ phpXX-php-ext  (GHA cached, not pushed)
#           └─▶ phpXX-base        (GHA cached, pushed)
#                 └─▶ phpXX-secure-int  (GHA cached, not pushed)
#                       └─▶ phpXX-secure    (GHA cached, pushed)
#                             └─▶ phpXX-advance  (GHA cached, pushed)
#
# Key variables (all overridable via environment variables):
#   REPO                 Docker Hub repository                   (devpanel/php)
#   TAG_SUFFIX           Image tag suffix                        (-rc on non-main)
#   LATEST_PHP_VERSION   Highest PHP version dir in the repo     (8.3)
#   CODESERVER_VERSION   code-server version to pin ("" = auto)  ("")
#   CORERULESET_VERSION  ModSecurity CRS version                 (3.3.5)
#
# Targets that are never pushed to Docker Hub:
#   downloader, phpXX-php-ext, phpXX-secure-int
# All of these are still cached in GitHub Actions (type=gha, mode=max).

variable "REPO"                { default = "devpanel/php" }
variable "TAG_SUFFIX"          { default = "-rc"          }
variable "LATEST_PHP_VERSION"  { default = "8.3"          }
variable "CODESERVER_VERSION"  { default = ""             }
variable "CORERULESET_VERSION" { default = "3.3.5"        }

# ─── Cache helpers ────────────────────────────────────────────────────────────
# GHA cache is always enabled; mode=max caches all intermediate layers.
function "cache_from" {
  params = [scope]
  result = ["type=gha,scope=${scope}"]
}

function "cache_to" {
  params = [scope]
  result = ["type=gha,scope=${scope},mode=max"]
}

# ─── Shared downloader (NOT pushed, cached in GHA) ───────────────────────────
# Downloads code-server .deb and libsodium source; both are version-independent.
# Referenced by every phpXX-php-ext target via the 'common-downloader'
# named context.
target "downloader" {
  dockerfile = "base/Dockerfile"
  context    = "base"
  target     = "downloader"
  platforms  = ["linux/amd64", "linux/arm64"]
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
# Contains all extensions and packages common to every version.
# Version-specific differences (avif, pcre, gd flags, imagick method, etc.)
# are in each {version}/base/Dockerfile.
#
# Referenced by phpXX-base targets via the 'common-php-ext' named context.

target "_php-ext-common" {
  dockerfile = "base/Dockerfile"
  target     = "php-ext-common"
  context    = "base"
  contexts = {
    common-downloader = "target:downloader"
    common            = "./base"
  }
  platforms  = ["linux/amd64", "linux/arm64"]
  secret     = ["id=github_token"]
  # No tags → not pushed to Docker Hub
}

target "php74-php-ext" {
  inherits = ["_php-ext-common"]
  args     = { PHP_VERSION = "7.4" }
  cache-from = cache_from("php74-php-ext")
  cache-to   = cache_to("php74-php-ext")
}

target "php80-php-ext" {
  inherits = ["_php-ext-common"]
  args     = { PHP_VERSION = "8.0" }
  cache-from = cache_from("php80-php-ext")
  cache-to   = cache_to("php80-php-ext")
}

target "php81-php-ext" {
  inherits = ["_php-ext-common"]
  args     = { PHP_VERSION = "8.1" }
  cache-from = cache_from("php81-php-ext")
  cache-to   = cache_to("php81-php-ext")
}

target "php82-php-ext" {
  inherits = ["_php-ext-common"]
  args     = { PHP_VERSION = "8.2" }
  cache-from = cache_from("php82-php-ext")
  cache-to   = cache_to("php82-php-ext")
}

target "php83-php-ext" {
  inherits = ["_php-ext-common"]
  args     = { PHP_VERSION = "8.3" }
  cache-from = cache_from("php83-php-ext")
  cache-to   = cache_to("php83-php-ext")
}

# ─── Base final images ────────────────────────────────────────────────────────
# Each version has its own Dockerfile containing only version-specific
# differences (gd/avif, pcre, PECL extensions, tool versions).
# 'common-php-ext' provides the shared php-ext intermediate without a registry
# push.  'common-downloader' provides code-server .deb.  'common' exposes
# ./base/ for any remaining shared assets.

target "_base-common" {
  platforms  = ["linux/amd64", "linux/arm64"]
  secret     = ["id=github_token"]
}

target "php74-base" {
  inherits   = ["_base-common"]
  dockerfile = "7.4/base/Dockerfile"
  context    = "7.4/base"
  contexts = {
    common-php-ext    = "target:php74-php-ext"
    common-downloader = "target:downloader"
    common            = "./base"
  }
  tags       = ["${REPO}:7.4-base${TAG_SUFFIX}"]
  cache-from = cache_from("php74-base")
  cache-to   = cache_to("php74-base")
}

target "php80-base" {
  inherits   = ["_base-common"]
  dockerfile = "8.0/base/Dockerfile"
  context    = "8.0/base"
  contexts = {
    common-php-ext    = "target:php80-php-ext"
    common-downloader = "target:downloader"
    common            = "./base"
  }
  tags       = ["${REPO}:8.0-base${TAG_SUFFIX}"]
  cache-from = cache_from("php80-base")
  cache-to   = cache_to("php80-base")
}

target "php81-base" {
  inherits   = ["_base-common"]
  dockerfile = "8.1/base/Dockerfile"
  context    = "8.1/base"
  contexts = {
    common-php-ext    = "target:php81-php-ext"
    common-downloader = "target:downloader"
    common            = "./base"
  }
  tags       = ["${REPO}:8.1-base${TAG_SUFFIX}"]
  cache-from = cache_from("php81-base")
  cache-to   = cache_to("php81-base")
}

target "php82-base" {
  inherits   = ["_base-common"]
  dockerfile = "8.2/base/Dockerfile"
  context    = "8.2/base"
  contexts = {
    common-php-ext    = "target:php82-php-ext"
    common-downloader = "target:downloader"
    common            = "./base"
  }
  tags       = ["${REPO}:8.2-base${TAG_SUFFIX}"]
  cache-from = cache_from("php82-base")
  cache-to   = cache_to("php82-base")
}

target "php83-base" {
  inherits   = ["_base-common"]
  dockerfile = "8.3/base/Dockerfile"
  context    = "8.3/base"
  contexts = {
    common-php-ext    = "target:php83-php-ext"
    common-downloader = "target:downloader"
    common            = "./base"
  }
  tags       = ["${REPO}:8.3-base${TAG_SUFFIX}"]
  cache-from = cache_from("php83-base")
  cache-to   = cache_to("php83-base")
}

# ─── Secure intermediate targets (NOT pushed, cached in GHA) ─────────────────
# Built from the shared secure/Dockerfile on top of each version's base image.

target "_secure-int-common" {
  dockerfile = "secure/Dockerfile"
  context    = "secure"
  platforms  = ["linux/amd64", "linux/arm64"]
  args       = { BASE_IMAGE = "base-image", CORERULESET_VERSION = CORERULESET_VERSION }
  # No tags → not pushed to Docker Hub
}

target "php74-secure-int" {
  inherits   = ["_secure-int-common"]
  contexts   = { base-image = "target:php74-base" }
  cache-from = cache_from("php74-secure-int")
  cache-to   = cache_to("php74-secure-int")
}

target "php80-secure-int" {
  inherits   = ["_secure-int-common"]
  contexts   = { base-image = "target:php80-base" }
  cache-from = cache_from("php80-secure-int")
  cache-to   = cache_to("php80-secure-int")
}

target "php81-secure-int" {
  inherits   = ["_secure-int-common"]
  contexts   = { base-image = "target:php81-base" }
  cache-from = cache_from("php81-secure-int")
  cache-to   = cache_to("php81-secure-int")
}

target "php82-secure-int" {
  inherits   = ["_secure-int-common"]
  contexts   = { base-image = "target:php82-base" }
  cache-from = cache_from("php82-secure-int")
  cache-to   = cache_to("php82-secure-int")
}

target "php83-secure-int" {
  inherits   = ["_secure-int-common"]
  contexts   = { base-image = "target:php83-base" }
  cache-from = cache_from("php83-secure-int")
  cache-to   = cache_to("php83-secure-int")
}

# ─── Secure final images ──────────────────────────────────────────────────────

target "_secure-common" {
  platforms  = ["linux/amd64", "linux/arm64"]
  args       = { BASE_IMAGE = "secure-intermediate" }
}

target "php74-secure" {
  inherits   = ["_secure-common"]
  dockerfile = "7.4/secure/Dockerfile"
  context    = "7.4/secure"
  contexts   = { secure-intermediate = "target:php74-secure-int" }
  tags       = ["${REPO}:7.4-secure${TAG_SUFFIX}"]
  cache-from = cache_from("php74-secure")
  cache-to   = cache_to("php74-secure")
}

target "php80-secure" {
  inherits   = ["_secure-common"]
  dockerfile = "8.0/secure/Dockerfile"
  context    = "8.0/secure"
  contexts   = { secure-intermediate = "target:php80-secure-int" }
  tags       = ["${REPO}:8.0-secure${TAG_SUFFIX}"]
  cache-from = cache_from("php80-secure")
  cache-to   = cache_to("php80-secure")
}

target "php81-secure" {
  inherits   = ["_secure-common"]
  dockerfile = "8.1/secure/Dockerfile"
  context    = "8.1/secure"
  contexts   = { secure-intermediate = "target:php81-secure-int" }
  tags       = ["${REPO}:8.1-secure${TAG_SUFFIX}"]
  cache-from = cache_from("php81-secure")
  cache-to   = cache_to("php81-secure")
}

target "php82-secure" {
  inherits   = ["_secure-common"]
  dockerfile = "8.2/secure/Dockerfile"
  context    = "8.2/secure"
  contexts   = { secure-intermediate = "target:php82-secure-int" }
  tags       = ["${REPO}:8.2-secure${TAG_SUFFIX}"]
  cache-from = cache_from("php82-secure")
  cache-to   = cache_to("php82-secure")
}

target "php83-secure" {
  inherits   = ["_secure-common"]
  dockerfile = "8.3/secure/Dockerfile"
  context    = "8.3/secure"
  contexts   = { secure-intermediate = "target:php83-secure-int" }
  tags       = ["${REPO}:8.3-secure${TAG_SUFFIX}"]
  cache-from = cache_from("php83-secure")
  cache-to   = cache_to("php83-secure")
}

# ─── Advance final images ─────────────────────────────────────────────────────
# All versions use the same advance/Dockerfile; only the base image differs.

target "_advance-common" {
  dockerfile = "advance/Dockerfile"
  context    = "advance"
  platforms  = ["linux/amd64", "linux/arm64"]
  args       = { BASE_IMAGE = "base-image" }
}

target "php74-advance" {
  inherits   = ["_advance-common"]
  contexts   = { base-image = "target:php74-secure" }
  tags       = ["${REPO}:7.4-advance${TAG_SUFFIX}"]
  cache-from = cache_from("php74-advance")
  cache-to   = cache_to("php74-advance")
}

target "php80-advance" {
  inherits   = ["_advance-common"]
  contexts   = { base-image = "target:php80-secure" }
  tags       = ["${REPO}:8.0-advance${TAG_SUFFIX}"]
  cache-from = cache_from("php80-advance")
  cache-to   = cache_to("php80-advance")
}

target "php81-advance" {
  inherits   = ["_advance-common"]
  contexts   = { base-image = "target:php81-secure" }
  tags       = ["${REPO}:8.1-advance${TAG_SUFFIX}"]
  cache-from = cache_from("php81-advance")
  cache-to   = cache_to("php81-advance")
}

target "php82-advance" {
  inherits   = ["_advance-common"]
  contexts   = { base-image = "target:php82-secure" }
  tags       = ["${REPO}:8.2-advance${TAG_SUFFIX}"]
  cache-from = cache_from("php82-advance")
  cache-to   = cache_to("php82-advance")
}

target "php83-advance" {
  inherits   = ["_advance-common"]
  contexts   = { base-image = "target:php83-secure" }
  tags       = ["${REPO}:8.3-advance${TAG_SUFFIX}"]
  cache-from = cache_from("php83-advance")
  cache-to   = cache_to("php83-advance")
}
