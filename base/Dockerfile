# syntax=docker/dockerfile:1
# ─── Artifact downloader ───────────────────────────────────────────────────
# Uses php:${LATEST_PHP_VERSION}-apache as base so that its OS layers are
# identical to those of the highest PHP version we build.  Downloads large,
# version-independent binaries (code-server, libsodium) shared across all
# PHP version builds via Docker Bake's named-context mechanism.
#
# This stage is referenced by every {version}/base/Dockerfile through the
# 'common-downloader' named context in docker-bake.hcl.  It is cached in
# GitHub Actions (type=gha) but never pushed to Docker Hub.
ARG LATEST_PHP_VERSION=8.3
FROM php:${LATEST_PHP_VERSION}-apache AS downloader

ARG CODESERVER_MAJOR_VERSION=4
ARG CODESERVER_PINNED_HASH_VERSION=4.99.4
ARG CODESERVER_VERSION=$CODESERVER_PINNED_HASH_VERSION
ARG CODESERVER_DEB_SHA256_AMD64=74c107b33643ed11223263b86431530fbc9c9f7c8202997579a6f0c41b4cb102
ARG CODESERVER_DEB_SHA256_ARM64=ae12d6300736dd742de3f5aef1b80c996c4b164ed385992e5de9d55f1e2077c3

# Download libsodium source (pinned release, identical for every PHP version)
RUN mkdir -p /tmp/libsodium \
    && curl -sL https://github.com/jedisct1/libsodium/archive/1.0.18-RELEASE.tar.gz \
       | tar xzf - -C /tmp/libsodium

# Download code-server deb (identical binary for every PHP version).
# php -r is used for the optional dynamic-version resolution.
RUN --mount=type=secret,id=github_token,env=GITHUB_TOKEN \
  set -e; \
  if [ -z "$CODESERVER_VERSION" ]; then \
    if [ -n "${GITHUB_TOKEN:-}" ]; then \
      RELEASES_JSON="$(curl -fsSL --retry 5 --retry-all-errors --connect-timeout 10 \
        -H 'Accept: application/vnd.github+json' \
        -H 'X-GitHub-Api-Version: 2022-11-28' \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        https://api.github.com/repos/coder/code-server/releases?per_page=100)"; \
    else \
      RELEASES_JSON="$(curl -fsSL --retry 5 --retry-all-errors --connect-timeout 10 \
        -H 'Accept: application/vnd.github+json' \
        -H 'X-GitHub-Api-Version: 2022-11-28' \
        https://api.github.com/repos/coder/code-server/releases?per_page=100)"; \
    fi; \
  CODESERVER_VERSION="$(printf '%s' "$RELEASES_JSON" | php -r ' \
$major = $argv[1]; \
$releases = json_decode(stream_get_contents(STDIN), true); \
 \
if (!is_array($releases)) { \
  fwrite(STDERR, "Failed to parse releases JSON\n"); \
  exit(2); \
} \
 \
foreach ($releases as $release) { \
  if (($release["draft"] ?? false) || ($release["prerelease"] ?? false)) { \
    continue; \
  } \
 \
  $tag = $release["tag_name"] ?? ""; \
  if (preg_match("/^v?" . preg_quote($major, "/") . "\\.[0-9]+\\.[0-9]+(?:[-+].*)?$/", $tag)) { \
    echo ltrim($tag, "v"); \
    exit(0); \
  } \
} \
 \
exit(1); \
' "$CODESERVER_MAJOR_VERSION")" || { echo "Unable to resolve code-server major $CODESERVER_MAJOR_VERSION from GitHub releases" >&2; exit 1; }; \
  fi; \
  # code-server is required: fail build if version is empty
  [ -n "$CODESERVER_VERSION" ] || { echo "CODESERVER_VERSION is empty" >&2; exit 1; }; \
  DEB_ARCH="$(dpkg --print-architecture)"; \
  case "$DEB_ARCH" in amd64|arm64) ;; *) echo "Unsupported architecture for code-server: $DEB_ARCH" >&2; exit 1 ;; esac; \
  DEB_URL="https://github.com/coder/code-server/releases/download/v${CODESERVER_VERSION}/code-server_${CODESERVER_VERSION}_${DEB_ARCH}.deb"; \
  curl -fsSL --retry 5 --retry-all-errors --connect-timeout 10 "$DEB_URL" -o /tmp/code-server.deb; \
  if [ "$CODESERVER_VERSION" = "$CODESERVER_PINNED_HASH_VERSION" ]; then \
    case "$DEB_ARCH" in \
      amd64) DEB_SHA256="$CODESERVER_DEB_SHA256_AMD64" ;; \
      arm64) DEB_SHA256="$CODESERVER_DEB_SHA256_ARM64" ;; \
    esac; \
    echo "$DEB_SHA256 /tmp/code-server.deb" | sha256sum -c -; \
  fi

