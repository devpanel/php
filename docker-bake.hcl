# docker-bake.hcl — Docker Buildx Bake file for devpanel/php
#
# Intermediate stages (downloader, {v}-secure-int) are cached in GitHub
# Actions cache (type=gha) but NEVER pushed to Docker Hub.  Final images
# ({v}-base, {v}-secure, {v}-advance) are pushed.
#
# Key variables (all overridable via environment variables):
#   REPO                 Docker Hub repository                   (devpanel/php)
#   TAG_SUFFIX           Image tag suffix                        (-rc on non-main)
#   LATEST_PHP_VERSION   Highest PHP version dir in the repo     (8.3)
#   CODESERVER_VERSION   code-server version to pin ("" = auto)  ("")
#   CORERULESET_VERSION  ModSecurity CRS version                 (3.3.5)
#   CACHE_TYPE           BuildKit cache backend type ("" = off)  (gha)

variable "REPO"                { default = "devpanel/php" }
variable "TAG_SUFFIX"          { default = "-rc"          }
variable "LATEST_PHP_VERSION"  { default = "8.3"          }
variable "CODESERVER_VERSION"  { default = ""             }
variable "CORERULESET_VERSION" { default = "3.3.5"        }
# Set CACHE_TYPE="" to disable caching (used by docker-build-all.yml)
variable "CACHE_TYPE"          { default = "gha"          }

# ─── Cache helpers ────────────────────────────────────────────────────────────
function "cache_from" {
  params = [scope]
  result = CACHE_TYPE != "" ? ["type=${CACHE_TYPE},scope=${scope}"] : []
}

function "cache_to" {
  params = [scope]
  result = CACHE_TYPE != "" ? ["type=${CACHE_TYPE},scope=${scope},mode=max"] : []
}

# ─── Build groups ─────────────────────────────────────────────────────────────
group "all" {
  targets = [
    "php74-base", "php74-secure", "php74-advance",
    "php80-base", "php80-secure", "php80-advance",
    "php81-base", "php81-secure", "php81-advance",
    "php82-base", "php82-secure", "php82-advance",
    "php83-base", "php83-secure", "php83-advance",
  ]
}

group "php74" { targets = ["php74-base", "php74-secure", "php74-advance"] }
group "php80" { targets = ["php80-base", "php80-secure", "php80-advance"] }
group "php81" { targets = ["php81-base", "php81-secure", "php81-advance"] }
group "php82" { targets = ["php82-base", "php82-secure", "php82-advance"] }
group "php83" { targets = ["php83-base", "php83-secure", "php83-advance"] }

# ─── Shared downloader (NOT pushed, cached in GHA) ───────────────────────────
# Downloads code-server .deb and libsodium source; both are version-independent.
# Referenced by every {version}/base/Dockerfile via the 'common-downloader'
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

# ─── Base final images ────────────────────────────────────────────────────────
# Each version has its own Dockerfile containing the php-ext stage (version-
# specific extension compilation) and the final stage (tools).
# The 'common-downloader' context provides pre-downloaded binaries without
# pushing the downloader stage.  The 'common' context exposes the ./base/
# directory so per-version Dockerfiles can COPY --from=common to get shared
# templates, scripts, bin/devpanel, and drush files.

target "php74-base" {
  dockerfile = "7.4/base/Dockerfile"
  context    = "7.4/base"
  contexts = {
    common-downloader = "target:downloader"
    common            = "./base"
  }
  platforms  = ["linux/amd64", "linux/arm64"]
  tags       = ["${REPO}:7.4-base${TAG_SUFFIX}"]
  cache-from = cache_from("php74-base")
  cache-to   = cache_to("php74-base")
}

target "php80-base" {
  dockerfile = "8.0/base/Dockerfile"
  context    = "8.0/base"
  contexts = {
    common-downloader = "target:downloader"
    common            = "./base"
  }
  platforms  = ["linux/amd64", "linux/arm64"]
  tags       = ["${REPO}:8.0-base${TAG_SUFFIX}"]
  cache-from = cache_from("php80-base")
  cache-to   = cache_to("php80-base")
}

target "php81-base" {
  dockerfile = "8.1/base/Dockerfile"
  context    = "8.1/base"
  contexts = {
    common-downloader = "target:downloader"
    common            = "./base"
  }
  platforms  = ["linux/amd64", "linux/arm64"]
  tags       = ["${REPO}:8.1-base${TAG_SUFFIX}"]
  cache-from = cache_from("php81-base")
  cache-to   = cache_to("php81-base")
}

target "php82-base" {
  dockerfile = "8.2/base/Dockerfile"
  context    = "8.2/base"
  contexts = {
    common-downloader = "target:downloader"
    common            = "./base"
  }
  platforms  = ["linux/amd64", "linux/arm64"]
  tags       = ["${REPO}:8.2-base${TAG_SUFFIX}"]
  cache-from = cache_from("php82-base")
  cache-to   = cache_to("php82-base")
}

target "php83-base" {
  dockerfile = "8.3/base/Dockerfile"
  context    = "8.3/base"
  contexts = {
    common-downloader = "target:downloader"
    common            = "./base"
  }
  platforms  = ["linux/amd64", "linux/arm64"]
  tags       = ["${REPO}:8.3-base${TAG_SUFFIX}"]
  cache-from = cache_from("php83-base")
  cache-to   = cache_to("php83-base")
}

# ─── Secure intermediate targets (NOT pushed, cached in GHA) ─────────────────
# Built from the shared secure/Dockerfile on top of each version's base image.
# The 'base-image' context is satisfied locally by Docker Bake without a
# registry push.

target "php74-secure-int" {
  dockerfile = "secure/Dockerfile"
  context    = "secure"
  contexts   = { base-image = "target:php74-base" }
  platforms  = ["linux/amd64", "linux/arm64"]
  args       = { BASE_IMAGE = "base-image", CORERULESET_VERSION = CORERULESET_VERSION }
  cache-from = cache_from("php74-secure-int")
  cache-to   = cache_to("php74-secure-int")
  # No tags → not pushed to Docker Hub
}

target "php80-secure-int" {
  dockerfile = "secure/Dockerfile"
  context    = "secure"
  contexts   = { base-image = "target:php80-base" }
  platforms  = ["linux/amd64", "linux/arm64"]
  args       = { BASE_IMAGE = "base-image", CORERULESET_VERSION = CORERULESET_VERSION }
  cache-from = cache_from("php80-secure-int")
  cache-to   = cache_to("php80-secure-int")
}

target "php81-secure-int" {
  dockerfile = "secure/Dockerfile"
  context    = "secure"
  contexts   = { base-image = "target:php81-base" }
  platforms  = ["linux/amd64", "linux/arm64"]
  args       = { BASE_IMAGE = "base-image", CORERULESET_VERSION = CORERULESET_VERSION }
  cache-from = cache_from("php81-secure-int")
  cache-to   = cache_to("php81-secure-int")
}

target "php82-secure-int" {
  dockerfile = "secure/Dockerfile"
  context    = "secure"
  contexts   = { base-image = "target:php82-base" }
  platforms  = ["linux/amd64", "linux/arm64"]
  args       = { BASE_IMAGE = "base-image", CORERULESET_VERSION = CORERULESET_VERSION }
  cache-from = cache_from("php82-secure-int")
  cache-to   = cache_to("php82-secure-int")
}

target "php83-secure-int" {
  dockerfile = "secure/Dockerfile"
  context    = "secure"
  contexts   = { base-image = "target:php83-base" }
  platforms  = ["linux/amd64", "linux/arm64"]
  args       = { BASE_IMAGE = "base-image", CORERULESET_VERSION = CORERULESET_VERSION }
  cache-from = cache_from("php83-secure-int")
  cache-to   = cache_to("php83-secure-int")
}

# ─── Secure final images ──────────────────────────────────────────────────────
# Per-version Dockerfiles handle the multipart-rule removal (7.4 and 8.0 only).

target "php74-secure" {
  dockerfile = "7.4/secure/Dockerfile"
  context    = "7.4/secure"
  contexts   = { secure-intermediate = "target:php74-secure-int" }
  platforms  = ["linux/amd64", "linux/arm64"]
  args       = { BASE_IMAGE = "secure-intermediate" }
  tags       = ["${REPO}:7.4-secure${TAG_SUFFIX}"]
  cache-from = cache_from("php74-secure")
  cache-to   = cache_to("php74-secure")
}

target "php80-secure" {
  dockerfile = "8.0/secure/Dockerfile"
  context    = "8.0/secure"
  contexts   = { secure-intermediate = "target:php80-secure-int" }
  platforms  = ["linux/amd64", "linux/arm64"]
  args       = { BASE_IMAGE = "secure-intermediate" }
  tags       = ["${REPO}:8.0-secure${TAG_SUFFIX}"]
  cache-from = cache_from("php80-secure")
  cache-to   = cache_to("php80-secure")
}

target "php81-secure" {
  dockerfile = "8.1/secure/Dockerfile"
  context    = "8.1/secure"
  contexts   = { secure-intermediate = "target:php81-secure-int" }
  platforms  = ["linux/amd64", "linux/arm64"]
  args       = { BASE_IMAGE = "secure-intermediate" }
  tags       = ["${REPO}:8.1-secure${TAG_SUFFIX}"]
  cache-from = cache_from("php81-secure")
  cache-to   = cache_to("php81-secure")
}

target "php82-secure" {
  dockerfile = "8.2/secure/Dockerfile"
  context    = "8.2/secure"
  contexts   = { secure-intermediate = "target:php82-secure-int" }
  platforms  = ["linux/amd64", "linux/arm64"]
  args       = { BASE_IMAGE = "secure-intermediate" }
  tags       = ["${REPO}:8.2-secure${TAG_SUFFIX}"]
  cache-from = cache_from("php82-secure")
  cache-to   = cache_to("php82-secure")
}

target "php83-secure" {
  dockerfile = "8.3/secure/Dockerfile"
  context    = "8.3/secure"
  contexts   = { secure-intermediate = "target:php83-secure-int" }
  platforms  = ["linux/amd64", "linux/arm64"]
  args       = { BASE_IMAGE = "secure-intermediate" }
  tags       = ["${REPO}:8.3-secure${TAG_SUFFIX}"]
  cache-from = cache_from("php83-secure")
  cache-to   = cache_to("php83-secure")
}

# ─── Advance final images ─────────────────────────────────────────────────────
# All versions use the same advance/Dockerfile; only the base image differs.
# Common scripts/supervisor files live in advance/ (build context).

target "php74-advance" {
  dockerfile = "advance/Dockerfile"
  context    = "advance"
  contexts   = { base-image = "target:php74-secure" }
  platforms  = ["linux/amd64", "linux/arm64"]
  args       = { BASE_IMAGE = "base-image" }
  tags       = ["${REPO}:7.4-advance${TAG_SUFFIX}"]
  cache-from = cache_from("php74-advance")
  cache-to   = cache_to("php74-advance")
}

target "php80-advance" {
  dockerfile = "advance/Dockerfile"
  context    = "advance"
  contexts   = { base-image = "target:php80-secure" }
  platforms  = ["linux/amd64", "linux/arm64"]
  args       = { BASE_IMAGE = "base-image" }
  tags       = ["${REPO}:8.0-advance${TAG_SUFFIX}"]
  cache-from = cache_from("php80-advance")
  cache-to   = cache_to("php80-advance")
}

target "php81-advance" {
  dockerfile = "advance/Dockerfile"
  context    = "advance"
  contexts   = { base-image = "target:php81-secure" }
  platforms  = ["linux/amd64", "linux/arm64"]
  args       = { BASE_IMAGE = "base-image" }
  tags       = ["${REPO}:8.1-advance${TAG_SUFFIX}"]
  cache-from = cache_from("php81-advance")
  cache-to   = cache_to("php81-advance")
}

target "php82-advance" {
  dockerfile = "advance/Dockerfile"
  context    = "advance"
  contexts   = { base-image = "target:php82-secure" }
  platforms  = ["linux/amd64", "linux/arm64"]
  args       = { BASE_IMAGE = "base-image" }
  tags       = ["${REPO}:8.2-advance${TAG_SUFFIX}"]
  cache-from = cache_from("php82-advance")
  cache-to   = cache_to("php82-advance")
}

target "php83-advance" {
  dockerfile = "advance/Dockerfile"
  context    = "advance"
  contexts   = { base-image = "target:php83-secure" }
  platforms  = ["linux/amd64", "linux/arm64"]
  args       = { BASE_IMAGE = "base-image" }
  tags       = ["${REPO}:8.3-advance${TAG_SUFFIX}"]
  cache-from = cache_from("php83-advance")
  cache-to   = cache_to("php83-advance")
}
