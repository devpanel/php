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
#   TAG_SUFFIX                    Image tag suffix                        ("" on main, "-rc" on develop)
#   LATEST_PHP_VERSION            Highest PHP version dir in the repo     (8.3)
#   CODESERVER_VERSION            code-server version to pin ("" = auto)  ("")
#   CORERULESET_VERSION           ModSecurity CRS version                 (3.3.5)
#   CACHE_FROM_ENABLED            Read from GHA cache ("true"/"false")    ("true")
#   PLATFORMS                     Comma-separated target platforms        ("linux/amd64,linux/arm64")
#
# Targets that are never pushed to Docker Hub:
#   downloader, phpX_Y-php-ext, phpX_Y-secure-int
# All of these are still cached in GitHub Actions (type=gha, mode=max).
#
# Target names use underscores for the version segment (e.g. php8_3-base for
# PHP 8.3) because dots are the HCL attribute-access operator and are not
# valid in identifier names.
#
# PHP 7.4 and 8.0 run Debian 11 with mod_security 2.9.3, which doesn't support
# the REQUEST-922-MULTIPART-ATTACK rule, so they each have a per-version
# secure/Dockerfile that removes it.  PHP 8.1–8.3 use secure/Dockerfile directly.

variable "REPO"               { default = "devpanel/php"            }
variable "TAG_SUFFIX"         { default = ""                        }
variable "LATEST_PHP_VERSION" { default = "8.3"                    }
variable "CODESERVER_VERSION" { default = ""                        }
variable "CORERULESET_VERSION" { default = "3.3.5"                 }
variable "CACHE_FROM_ENABLED" { default = "true"                   }
variable "PLATFORMS"          { default = "linux/amd64,linux/arm64" }

# ─── Cache helpers ────────────────────────────────────────────────────────────
# cache_from: read from GHA cache (push workflow only; full-rebuild sets CACHE_FROM_ENABLED=false)
# cache_to:   always write to GHA cache (mode=max caches all intermediate layers)

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

# ─── Common php-ext base (NOT pushed, cached in GHA) ─────────────────────────
# Builds the php-ext-common stage from base/Dockerfile for each PHP version.
# Contains all extensions, packages, and tools common to every version.
# Version-specific differences (avif, pcre, gd flags, imagick method, etc.)
# are in each {version}/base/Dockerfile.

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

# php-ext intermediate — one explicit target per PHP version

target "php7_4-php-ext" {
  inherits   = ["_php-ext-common"]
  args       = { PHP_VERSION = "7.4" }
  cache-from = cache_from("php7_4-php-ext")
  cache-to   = cache_to("php7_4-php-ext")
}

target "php8_0-php-ext" {
  inherits   = ["_php-ext-common"]
  args       = { PHP_VERSION = "8.0" }
  cache-from = cache_from("php8_0-php-ext")
  cache-to   = cache_to("php8_0-php-ext")
}

target "php8_1-php-ext" {
  inherits   = ["_php-ext-common"]
  args       = { PHP_VERSION = "8.1" }
  cache-from = cache_from("php8_1-php-ext")
  cache-to   = cache_to("php8_1-php-ext")
}

target "php8_2-php-ext" {
  inherits   = ["_php-ext-common"]
  args       = { PHP_VERSION = "8.2" }
  cache-from = cache_from("php8_2-php-ext")
  cache-to   = cache_to("php8_2-php-ext")
}

target "php8_3-php-ext" {
  inherits   = ["_php-ext-common"]
  args       = { PHP_VERSION = "8.3" }
  cache-from = cache_from("php8_3-php-ext")
  cache-to   = cache_to("php8_3-php-ext")
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

target "php7_4-base" {
  inherits   = ["_base-common"]
  dockerfile = "7.4/base/Dockerfile"
  context    = "7.4/base"
  contexts = {
    common-php-ext    = "target:php7_4-php-ext"
    common-downloader = "target:downloader"
    common            = "./base"
  }
  tags       = ["${REPO}:7.4-base${TAG_SUFFIX}"]
  cache-from = cache_from("php7_4-base")
  cache-to   = cache_to("php7_4-base")
}

target "php8_0-base" {
  inherits   = ["_base-common"]
  dockerfile = "8.0/base/Dockerfile"
  context    = "8.0/base"
  contexts = {
    common-php-ext    = "target:php8_0-php-ext"
    common-downloader = "target:downloader"
    common            = "./base"
  }
  tags       = ["${REPO}:8.0-base${TAG_SUFFIX}"]
  cache-from = cache_from("php8_0-base")
  cache-to   = cache_to("php8_0-base")
}

target "php8_1-base" {
  inherits   = ["_base-common"]
  dockerfile = "8.1/base/Dockerfile"
  context    = "8.1/base"
  contexts = {
    common-php-ext    = "target:php8_1-php-ext"
    common-downloader = "target:downloader"
    common            = "./base"
  }
  tags       = ["${REPO}:8.1-base${TAG_SUFFIX}"]
  cache-from = cache_from("php8_1-base")
  cache-to   = cache_to("php8_1-base")
}

target "php8_2-base" {
  inherits   = ["_base-common"]
  dockerfile = "8.2/base/Dockerfile"
  context    = "8.2/base"
  contexts = {
    common-php-ext    = "target:php8_2-php-ext"
    common-downloader = "target:downloader"
    common            = "./base"
  }
  tags       = ["${REPO}:8.2-base${TAG_SUFFIX}"]
  cache-from = cache_from("php8_2-base")
  cache-to   = cache_to("php8_2-base")
}

target "php8_3-base" {
  inherits   = ["_base-common"]
  dockerfile = "8.3/base/Dockerfile"
  context    = "8.3/base"
  contexts = {
    common-php-ext    = "target:php8_3-php-ext"
    common-downloader = "target:downloader"
    common            = "./base"
  }
  tags       = ["${REPO}:8.3-base${TAG_SUFFIX}"]
  cache-from = cache_from("php8_3-base")
  cache-to   = cache_to("php8_3-base")
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

target "php7_4-secure-int" {
  inherits   = ["_secure-int-common"]
  contexts   = { base-image = "target:php7_4-base" }
  cache-from = cache_from("php7_4-secure-int")
  cache-to   = cache_to("php7_4-secure-int")
}

target "php8_0-secure-int" {
  inherits   = ["_secure-int-common"]
  contexts   = { base-image = "target:php8_0-base" }
  cache-from = cache_from("php8_0-secure-int")
  cache-to   = cache_to("php8_0-secure-int")
}

target "php8_1-secure-int" {
  inherits   = ["_secure-int-common"]
  contexts   = { base-image = "target:php8_1-base" }
  cache-from = cache_from("php8_1-secure-int")
  cache-to   = cache_to("php8_1-secure-int")
}

target "php8_2-secure-int" {
  inherits   = ["_secure-int-common"]
  contexts   = { base-image = "target:php8_2-base" }
  cache-from = cache_from("php8_2-secure-int")
  cache-to   = cache_to("php8_2-secure-int")
}

target "php8_3-secure-int" {
  inherits   = ["_secure-int-common"]
  contexts   = { base-image = "target:php8_3-base" }
  cache-from = cache_from("php8_3-secure-int")
  cache-to   = cache_to("php8_3-secure-int")
}

# ─── Secure final images ──────────────────────────────────────────────────────
# PHP 7.4 and 8.0 use a per-version Dockerfile that removes the
# REQUEST-922-MULTIPART-ATTACK rule (mod_security 2.9.3 on Debian 11 doesn't
# support it).  PHP 8.1–8.3 use the shared 'final' stage from secure/Dockerfile,
# which just inherits USER/WORKDIR/CMD from secure-intermediate without adding
# new layers.

target "_secure-common" {
  platforms  = split(",", PLATFORMS)
  args       = { BASE_IMAGE = "secure-intermediate" }
  target     = "final"
}

# 7.4 and 8.0: per-version Dockerfiles remove the MULTIPART rule

target "php7_4-secure" {
  inherits   = ["_secure-common"]
  dockerfile = "7.4/secure/Dockerfile"
  context    = "7.4/secure"
  contexts   = { secure-intermediate = "target:php7_4-secure-int" }
  tags       = ["${REPO}:7.4-secure${TAG_SUFFIX}"]
  cache-from = cache_from("php7_4-secure")
  cache-to   = cache_to("php7_4-secure")
}

target "php8_0-secure" {
  inherits   = ["_secure-common"]
  dockerfile = "8.0/secure/Dockerfile"
  context    = "8.0/secure"
  contexts   = { secure-intermediate = "target:php8_0-secure-int" }
  tags       = ["${REPO}:8.0-secure${TAG_SUFFIX}"]
  cache-from = cache_from("php8_0-secure")
  cache-to   = cache_to("php8_0-secure")
}

# 8.1–8.3: use the shared secure/Dockerfile final stage directly

target "php8_1-secure" {
  inherits   = ["_secure-common"]
  dockerfile = "secure/Dockerfile"
  context    = "secure"
  contexts   = { secure-intermediate = "target:php8_1-secure-int" }
  tags       = ["${REPO}:8.1-secure${TAG_SUFFIX}"]
  cache-from = cache_from("php8_1-secure")
  cache-to   = cache_to("php8_1-secure")
}

target "php8_2-secure" {
  inherits   = ["_secure-common"]
  dockerfile = "secure/Dockerfile"
  context    = "secure"
  contexts   = { secure-intermediate = "target:php8_2-secure-int" }
  tags       = ["${REPO}:8.2-secure${TAG_SUFFIX}"]
  cache-from = cache_from("php8_2-secure")
  cache-to   = cache_to("php8_2-secure")
}

target "php8_3-secure" {
  inherits   = ["_secure-common"]
  dockerfile = "secure/Dockerfile"
  context    = "secure"
  contexts   = { secure-intermediate = "target:php8_3-secure-int" }
  tags       = ["${REPO}:8.3-secure${TAG_SUFFIX}"]
  cache-from = cache_from("php8_3-secure")
  cache-to   = cache_to("php8_3-secure")
}

# ─── Advance final images ─────────────────────────────────────────────────────
# All versions use the same advance/Dockerfile; only the base image differs.

target "_advance-common" {
  dockerfile = "advance/Dockerfile"
  context    = "advance"
  platforms  = split(",", PLATFORMS)
  args       = { BASE_IMAGE = "base-image" }
}

target "php7_4-advance" {
  inherits   = ["_advance-common"]
  contexts   = { base-image = "target:php7_4-secure" }
  tags       = ["${REPO}:7.4-advance${TAG_SUFFIX}"]
  cache-from = cache_from("php7_4-advance")
  cache-to   = cache_to("php7_4-advance")
}

target "php8_0-advance" {
  inherits   = ["_advance-common"]
  contexts   = { base-image = "target:php8_0-secure" }
  tags       = ["${REPO}:8.0-advance${TAG_SUFFIX}"]
  cache-from = cache_from("php8_0-advance")
  cache-to   = cache_to("php8_0-advance")
}

target "php8_1-advance" {
  inherits   = ["_advance-common"]
  contexts   = { base-image = "target:php8_1-secure" }
  tags       = ["${REPO}:8.1-advance${TAG_SUFFIX}"]
  cache-from = cache_from("php8_1-advance")
  cache-to   = cache_to("php8_1-advance")
}

target "php8_2-advance" {
  inherits   = ["_advance-common"]
  contexts   = { base-image = "target:php8_2-secure" }
  tags       = ["${REPO}:8.2-advance${TAG_SUFFIX}"]
  cache-from = cache_from("php8_2-advance")
  cache-to   = cache_to("php8_2-advance")
}

target "php8_3-advance" {
  inherits   = ["_advance-common"]
  contexts   = { base-image = "target:php8_3-secure" }
  tags       = ["${REPO}:8.3-advance${TAG_SUFFIX}"]
  cache-from = cache_from("php8_3-advance")
  cache-to   = cache_to("php8_3-advance")
}
