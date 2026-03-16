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
ARG PHP_VERSION=8.3
FROM php:${LATEST_PHP_VERSION}-apache AS downloader

ARG CODESERVER_MAJOR_VERSION=4
ARG CODESERVER_PINNED_HASH_VERSION=4.99.4
ARG CODESERVER_VERSION=$CODESERVER_PINNED_HASH_VERSION
ARG CODESERVER_DEB_SHA256_AMD64=74c107b33643ed11223263b86431530fbc9c9f7c8202997579a6f0c41b4cb102
ARG CODESERVER_DEB_SHA256_ARM64=ae12d6300736dd742de3f5aef1b80c996c4b164ed385992e5de9d55f1e2077c3

# GitHub Copilot Chat is not available in the Open VSX marketplace used by
# code-server, so we download it directly from the VS Marketplace.
#
# Version channels
# ──────────────────────────────────
# The Copilot Chat extension publishes two channels to the VS Marketplace:
#   • Stable releases use simple MAJOR.MINOR.PATCH version numbers
#     (e.g. 0.26.7, visible as "0.26.0 … 0.26.7" in the VS Code desktop UI).
#   • Pre-release builds use a build-date-stamped format: MAJOR.MINOR.YYYYMMDDNN
#     (e.g. 0.26.2025040204 = series 0.26, released 2025-04-02, build 04).
# Only stable releases are used (see auto-detect logic below).
# Production Docker Bake builds pass COPILOT_CHAT_VERSION="" (the default in
# docker-bake.hcl), which overrides the Dockerfile default and triggers the
# auto-detection block below.  Auto-detection queries the VS Marketplace API
# and returns only the latest STABLE release whose engine requirement is
# satisfied by the bundled VS Code version.
# code-server 4.X.Y bundles VS Code 1.X.Y (e.g. 4.99.4 → VS Code 1.99.4).
#
# Pinned version
# ──────────────
# COPILOT_CHAT_PINNED_VERSION is the Dockerfile default: a known-good stable
# release compatible with code-server 4.99.4 (VS Code 1.99.4).  It is used
# when COPILOT_CHAT_VERSION is not overridden (e.g. a plain `docker build .`
# without Bake).  The CI "Verify Copilot Chat VSIX" job downloads the pinned
# version from the VS Marketplace API, confirms the file is a valid ZIP, and
# verifies the SHA256.
#
# To update the pin, download the new VSIX from the VS Marketplace API URL with
# --compressed so curl decompresses the gzip transfer encoding (required):
#   curl -fsSL --compressed \
#     "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/GitHub/vsextensions/copilot-chat/<ver>/vspackage" \
#     -o copilot-chat-<ver>.vsix
# Then run: sha256sum copilot-chat-<ver>.vsix
# Update COPILOT_CHAT_PINNED_VERSION and COPILOT_CHAT_VSIX_SHA256 below
# (see README for step-by-step instructions).
ARG COPILOT_CHAT_PINNED_VERSION=0.26.7
# COPILOT_CHAT_VERSION: defaults to COPILOT_CHAT_PINNED_VERSION (the same
# pattern used by CODESERVER_VERSION above).  Docker Bake passes an explicit
# empty string to trigger auto-detection and use the latest STABLE release
# compatible with the bundled VS Code version.  Pass an explicit non-empty
# version to reproduce a specific build with SHA verification.
ARG COPILOT_CHAT_VERSION=$COPILOT_CHAT_PINNED_VERSION
# SHA256 of the VSIX downloaded from the VS Marketplace vspackage endpoint for
# COPILOT_CHAT_PINNED_VERSION (architecture-independent).
# The integrity check only runs when the downloaded version equals the pinned
# version AND this value is non-empty.
ARG COPILOT_CHAT_VSIX_SHA256=691e80194fdba0399879fd065a76b9b14b32bfd29818292e816a4522eb0330d1

# Install unzip and zip early so they are available for VSIX validation and
# repacking during the download step.
RUN apt-get update \
    && apt-get install -y --no-install-recommends unzip zip \
    && rm -rf /var/lib/apt/lists/*

# Download libsodium source (pinned release, identical for every PHP version)
RUN mkdir -p /tmp/libsodium \
    && curl -sL https://github.com/jedisct1/libsodium/archive/1.0.18-RELEASE.tar.gz \
       | tar xzf - -C /tmp/libsodium

# Download code-server deb and GitHub Copilot Chat VSIX.
# php -r is used for the optional dynamic-version resolution of both.
# Both downloads are in the same RUN step so that the resolved
# CODESERVER_VERSION is available when auto-detecting COPILOT_CHAT_VERSION.
RUN --mount=type=secret,id=github_token,env=GITHUB_TOKEN,required=false \
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
  fi; \
  \
  # Download GitHub Copilot Chat VSIX (not available in Open VSX marketplace). \
  # If COPILOT_CHAT_VERSION is empty, detect the latest stable version compatible \
  # with the VS Code release bundled in this code-server version. \
  # code-server 4.X.Y bundles VS Code 1.X.Y (e.g. 4.99.4 → 1.99.4). \
  # Only stable releases are considered: pre-release builds use a 10-digit \
  # date-stamped patch component (YYYYMMDDNN, e.g. 2025040204) which is excluded \
  # by limiting the patch to at most 9 digits (< 10^9, i.e. not a date-stamp). \
  if [ -z "$COPILOT_CHAT_VERSION" ]; then \
    VSCODE_VERSION="$(printf '%s' "$CODESERVER_VERSION" | sed 's/^[0-9][0-9]*\./1./')"; \
    MARKETPLACE_JSON="$(curl -fsSL --retry 5 --retry-all-errors --connect-timeout 10 \
      -X POST \
      -H 'Content-Type: application/json' \
      -H 'Accept: application/json;api-version=3.0-preview.1' \
      -d '{"filters":[{"criteria":[{"filterType":7,"value":"GitHub.copilot-chat"}],"pageSize":100}],"flags":17}' \
      'https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery')"; \
    COPILOT_CHAT_VERSION="$(printf '%s' "$MARKETPLACE_JSON" | php -r ' \
$vscode_version = $argv[1]; \
$response = json_decode(stream_get_contents(STDIN), true); \
 \
if (!is_array($response)) { \
  fwrite(STDERR, "Failed to parse Marketplace API response\n"); \
  exit(2); \
} \
 \
$versions = $response["results"][0]["extensions"][0]["versions"] ?? []; \
foreach ($versions as $v) { \
  $ver = $v["version"] ?? ""; \
  if (!preg_match("/^\d+\.\d+\.\d{1,9}$/", $ver)) continue; \
  $engine = ""; \
  foreach ($v["properties"] ?? [] as $p) { \
    if ($p["key"] === "Microsoft.VisualStudio.Code.Engine") { \
      $engine = preg_replace("/^[\\^~>=]+/", "", $p["value"]); \
      $engine = preg_replace("/-.*$/", "", $engine); \
      break; \
    } \
  } \
  if (empty($engine)) continue; \
  if (version_compare($vscode_version, $engine, ">=")) { echo $ver; exit(0); } \
} \
fwrite(STDERR, "No compatible copilot-chat version found for VS Code " . $vscode_version . "\n"); \
exit(1); \
' "$VSCODE_VERSION")" || { echo "Unable to auto-detect copilot-chat version for VS Code $VSCODE_VERSION (check preceding errors)" >&2; exit 1; }; \
  fi; \
  # Validate the version matches semver major.minor.patch with optional pre-release/
  # build metadata using only URL-safe characters. This prevents a malformed URL
  # from being constructed: an empty string, path separator, or other unexpected
  # value is caught here with a clear message rather than silently producing
  # .../copilot-chat//vspackage or similar.
  printf '%s\n' "$COPILOT_CHAT_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z._-]*)?$' \
    || { echo "COPILOT_CHAT_VERSION has unexpected format: '${COPILOT_CHAT_VERSION}' (expected semver e.g. 1.2.3)" >&2; exit 1; }; \
  echo "Downloading Copilot Chat VSIX version: $COPILOT_CHAT_VERSION" >&2; \
  VSIX_URL="https://marketplace.visualstudio.com/_apis/public/gallery/publishers/GitHub/vsextensions/copilot-chat/${COPILOT_CHAT_VERSION}/vspackage"; \
  curl -fsSL --compressed --retry 5 --retry-all-errors --connect-timeout 10 "$VSIX_URL" -o /tmp/copilot-chat.vsix; \
  if [ "$COPILOT_CHAT_VERSION" = "$COPILOT_CHAT_PINNED_VERSION" ] && [ -n "$COPILOT_CHAT_VSIX_SHA256" ]; then \
    echo "$COPILOT_CHAT_VSIX_SHA256  /tmp/copilot-chat.vsix" | sha256sum -c -; \
  fi; \
  # Verify the download is a valid ZIP (VSIX is a ZIP archive).
  # A ZIP file starts with the PK magic bytes: 50 4b 03 04 (hex).
  # If the Marketplace returned an error page or rate-limit HTML instead of
  # the binary, this guard gives a clear diagnostic rather than a cryptic
  # "cannot find zipfile directory" message from unzip.
  if ! od -An -tx1 -N4 /tmp/copilot-chat.vsix | tr -d ' \n' | grep -qi '^504b0304'; then \
    ACTUAL_MAGIC="$(od -An -tx1 -N8 /tmp/copilot-chat.vsix | tr -d ' \n')"; \
    echo "Copilot Chat VSIX is not a valid ZIP (expected magic 504b0304, got: ${ACTUAL_MAGIC})." >&2; \
    echo "The Marketplace may have returned a rate-limit/error page instead of the binary." >&2; \
    echo "If the first bytes are 1f8b (gzip), re-run with --compressed on the curl command." >&2; \
    exit 1; \
  fi; \
  unzip -q /tmp/copilot-chat.vsix -d /tmp/_vsix_repack \
    || { echo "Failed to extract copilot-chat.vsix — file may be invalid or not a valid ZIP/VSIX (check marketplace response)" >&2; \
         exit 1; }

# Repack the Copilot Chat VSIX to use only standard deflate (method 8) or stored
# (method 0) compression.  Newer VS Marketplace packages may use Deflate64
# (method 9) or other methods unsupported by the yauzl library bundled with
# code-server, causing a fatal "Extract" error at install time.  Repacking with
# the system zip utility (which only emits methods 0 and 8) ensures the VSIX can
# be installed by any code-server version.
# TODO: Remove this repack step once code-server upgrades yauzl (or its bundled
# VS Code) to a version that supports Deflate64 (method 9) natively.
# The files were already unpacked into /tmp/_vsix_repack by the download step
# above.  The repack is skipped only if that directory does not exist (e.g. a
# cache hit on a layer predating this code).  The original file is kept until the
# repacked archive is fully written to avoid silently losing the VSIX on failure.
RUN if [ -d /tmp/_vsix_repack ]; then \
         ( cd /tmp/_vsix_repack && zip -r -9 /tmp/copilot-chat-repacked.vsix . ) \
         && mv /tmp/copilot-chat-repacked.vsix /tmp/copilot-chat.vsix \
         && rm -rf /tmp/_vsix_repack; \
       fi

# ─── Common PHP extensions stage ──────────────────────────────────────────────
# Builds the shared intermediate that all per-version Dockerfiles extend.
# Only packages and extensions that are IDENTICAL across all PHP versions are
# here.  Version-specific items (avif/pcre packages, gd configure flags,
# igbinary version pin, imagick build method, oauth, xdebug) live in each
# {version}/base/Dockerfile.
#
# This stage is referenced as the 'common-php-ext' Bake named context.
# It is cached in GitHub Actions (type=gha) but never pushed to Docker Hub.
FROM php:${PHP_VERSION}-apache AS php-ext-common

#== System Environments
ARG DEBIAN_FRONTEND=noninteractive
ENV USER=www
ENV GROUP=www
ENV UID=1000
ENV GID=1000
ENV HOME=/home/www
ENV SHELL=/bin/bash

#== Default Environments
ENV APP_ROOT=/var/www/html
ENV WEB_ROOT=$APP_ROOT
ENV PHP_CUSTOM_INI=$APP_ROOT/php.ini
ENV PHP_EXT_DIR=/usr/local/etc/php/conf.d

ENV PHP_MEMORY_LIMIT=4096M
ENV PHP_MAX_EXECUTION_TIME=600
ENV PHP_MAX_INPUT_TIME=600
ENV PHP_MAX_INPUT_VARS=3000
ENV PHP_UPLOAD_MAX_FILESIZE=64M
ENV PHP_POST_MAX_SIZE=64M
ENV PHP_CLEAR_ENV=false

ENV SERVER_NAME=default

ENV CODES_PORT=8080
ENV CODES_WORKING_DIR=$APP_ROOT
ENV CODES_USER_DATA_DIR=$APP_ROOT/.vscode
ENV CODES_ENABLE=yes

# Install packages common to all PHP versions.
# NOTE: libavif-dev (8.1+), libpcre2-dev (8.0+), and libpcre3/libpcre3-dev (7.4)
# are version-specific and therefore NOT included here.
# Dpkg::Use-Pty "0" is the log-friendly dpkg configuration: it disables the
# PTY-based progress reporting that produces "(Reading database ... N%)" noise,
# while leaving all real dpkg output (package names, errors, warnings) intact.
# The config file is written at the start and removed at the end of the same RUN
# instruction so it never persists into the final image.
# Retry up to 3 times to handle transient apt mirror/network failures (e.g. connection
# resets mid-download). seq generates the sequence so i takes values 1, 2, 3 in turn.
RUN echo 'Dpkg::Use-Pty "0";' > /etc/apt/apt.conf.d/01dpkg-no-pty \
    && for i in $(seq 1 3); do \
      apt-get update && apt-get upgrade -y \
        && apt-get install -y --no-install-recommends \
          apt-utils \
          sendmail-bin \
          sendmail \
          sudo \
          libbz2-dev \
          libjpeg62-turbo-dev \
          libpng-dev \
          libwebp-dev \
          libfreetype6-dev \
          libgeoip-dev \
          wget \
          libgmp-dev \
          libmagickwand-dev \
          libmagickcore-dev \
          libicu-dev \
          libldap2-dev \
          libpspell-dev \
          libtidy-dev \
          libxslt1-dev \
          libyaml-dev \
          libzip-dev \
          libmemcached-dev \
          libssl-dev \
          zlib1g-dev \
          zip unzip \
          git \
          rsync \
          ssh \
          default-mysql-client \
        && break \
      || { [ "$i" -lt 3 ] && sleep 5; }; \
    done \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/apt/apt.conf.d/01dpkg-no-pty

# Configure opcache (same for all versions)
RUN docker-php-ext-configure opcache --enable-opcache

# Install PHP extensions common to all versions.
# NOTE: gd is NOT here — its configure flags differ by version (avif support
# for 8.1+ vs no avif for 7.4/8.0).  Each version's Dockerfile
# runs docker-php-ext-configure gd and docker-php-ext-install gd separately.
RUN docker-php-ext-install -j$(nproc) \
      bcmath bz2 calendar exif gettext gmp intl mysqli opcache \
      pdo_mysql pspell shmop soap sockets sysvmsg sysvsem sysvshm \
      tidy xsl zip pcntl

# Install PECL extensions common to all versions (same version pins for all)
RUN pecl install -o -f \
      redis-5.3.7 \
      yaml-2.2.2 \
      memcached-3.2.0

# Install libsodium (source pre-downloaded in the 'downloader' stage)
COPY --from=common-downloader /tmp/libsodium /tmp/libsodium
RUN rm -f /usr/local/etc/php/conf.d/*sodium.ini \
    && rm -f /usr/local/lib/php/extensions/*/*sodium.so \
    && apt-get remove libsodium* -y \
    && cd /tmp/libsodium/libsodium-1.0.18-RELEASE/ \
    && ./configure && make && make check && make install \
    && cd / && rm -rf /tmp/libsodium \
    && pecl install -o -f libsodium

# Enable all common extensions.
# NOTE: gd, igbinary, imagick (and optionally xdebug, oauth) are enabled in
# the per-version Dockerfile after their version-specific build.
RUN docker-php-ext-enable \
      bcmath bz2 calendar exif gettext gmp intl mysqli opcache \
      pdo_mysql pspell redis shmop soap sockets sodium sysvmsg \
      sysvsem sysvshm tidy xsl yaml zip pcntl memcached

# Create the www user and configure sudo (root ops must happen before USER switch)
RUN groupadd -g ${GID} ${GROUP} \
    && useradd --system --shell /bin/bash --uid ${UID} --gid ${GROUP} \
               --create-home --home-dir /home/${USER} ${USER} \
    && adduser ${USER} www-data \
    && usermod -aG sudo ${USER} \
    && echo "www    ALL=(ALL:ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN mkdir -p ${APP_ROOT} && chown -R ${UID}:${GID} ${APP_ROOT}

RUN a2enmod rewrite remoteip headers

# Copy shared assets from the 'common' build context (./base/ directory).
# Per-version Dockerfiles may overlay version-specific files on top.
COPY --from=common bin/devpanel /usr/local/bin/devpanel
RUN chmod +x /usr/local/bin/devpanel && devpanel version
COPY --from=common templates /templates
COPY --from=common scripts   /scripts
COPY --from=common drush     /drush

# Install BEE CLI (identical across all PHP versions)
RUN mkdir /bee && git clone https://github.com/backdrop-contrib/bee.git /bee \
    && chmod +x /bee/bee.php \
    && ln -s /bee/bee.php /usr/bin/bee

# Install code-server (pre-downloaded in the 'downloader' stage)
COPY --from=common-downloader /tmp/code-server.deb /tmp/code-server.deb
RUN echo 'Dpkg::Use-Pty "0";' > /etc/apt/apt.conf.d/01dpkg-no-pty \
    && { dpkg -i /tmp/code-server.deb \
         || { apt-get update && apt-get install -y -f --no-install-recommends \
              && rm -rf /var/lib/apt/lists/* && dpkg -i /tmp/code-server.deb; }; } \
    && rm /tmp/code-server.deb \
    && rm -f /etc/apt/apt.conf.d/01dpkg-no-pty

# Pre-stage the GitHub Copilot Chat VSIX (repacked with standard Deflate above)
# so it is available after the USER switch for code-server to install below.
COPY --from=common-downloader /tmp/copilot-chat.vsix /tmp/copilot-chat.vsix

# Install Composer 2.x (default 2.3.10; PHP 8.3 overrides to 2.7.7 via self-update)
# and legacy Composer 1.x for projects that require it.
# 'composer2' bash alias is set after USER switch below.
RUN curl -fsSL https://getcomposer.org/installer \
      | php -- --install-dir=/usr/local/bin --filename=composer  --version=2.3.10 \
    && curl -fsSL https://getcomposer.org/installer \
      | php -- --install-dir=/usr/local/bin --filename=composer1 --version=1.10.16

# Install WP-CLI (default 2.9.0; PHP 7.4 per-version Dockerfile overrides with 2.4.0)
RUN curl -LO https://github.com/wp-cli/wp-cli/releases/download/v2.9.0/wp-cli-2.9.0.phar \
    && chmod +x wp-cli-2.9.0.phar \
    && mv wp-cli-2.9.0.phar /usr/local/bin/wp

ARG DRUSH_VERSION=8
RUN ln -s /drush/drush${DRUSH_VERSION}/vendor/bin/drush /usr/bin/drush \
    && mkdir -p /home/${USER}/.config/code-server \
    && rm -rf ${APP_ROOT} && mkdir -p ${APP_ROOT} \
    && chown -R ${USER}:${GROUP} /drush /bee /home/${USER} ${APP_ROOT}

USER ${USER}
WORKDIR ${APP_ROOT}

RUN touch /home/${USER}/.config/code-server/config.yaml

# Create the base directory for code-server extensions.
# This must be done as USER ${USER} so that code-server (which runs as the
# same user) can write into it when installing extensions.
RUN mkdir -p $CODES_USER_DATA_DIR/extensions

# Install GitHub Copilot Chat extension (not available in Open VSX marketplace).
# The VSIX was repacked above to use standard Deflate so code-server's bundled
# yauzl can extract it.  Installs into $CODES_USER_DATA_DIR/extensions so the
# extension is found with the existing --user-data-dir=$CODES_USER_DATA_DIR flag.
RUN code-server --extensions-dir $CODES_USER_DATA_DIR/extensions --install-extension /tmp/copilot-chat.vsix \
    && sudo rm /tmp/copilot-chat.vsix

# Bash alias for Composer 2.  The binary is installed as root above;
# the alias is set here (as the app user) to keep it in ~/.bashrc.
# composer1 is directly accessible as /usr/local/bin/composer1.
RUN composer update --working-dir=/drush/drush8 \
    && echo "alias composer2=/usr/local/bin/composer" >> ~/.bashrc \
    && echo "alias drush8=/drush/drush8/vendor/bin/drush" >> ~/.bashrc
RUN composer update --working-dir=/drush/drush9 \
    && echo "alias drush9=/drush/drush9/vendor/bin/drush" >> ~/.bashrc
RUN composer update --working-dir=/drush/drush10 \
    && echo "alias drush10=/drush/drush10/vendor/bin/drush" >> ~/.bashrc
RUN composer update --working-dir=/drush/drush11 \
    && echo "alias drush11=/drush/drush11/vendor/bin/drush" >> ~/.bashrc

RUN wget https://github.com/backdrop-contrib/backdrop-drush-extension/archive/refs/heads/1.x-1.x.zip \
    && unzip 1.x-1.x.zip -d /drush/drush${DRUSH_VERSION}/vendor/drush/drush/commands/backdrop \
    && /drush/drush${DRUSH_VERSION}/vendor/bin/drush cc drush

CMD ["sudo", "-E", "/bin/bash", "/scripts/apache-start.sh"]
