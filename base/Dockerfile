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


# ─── Common PHP extensions stage ──────────────────────────────────────────────
# Builds the shared intermediate that all per-version Dockerfiles extend.
# Only packages and extensions that are IDENTICAL across all PHP versions are
# here.  Version-specific items (avif/pcre packages, gd configure flags,
# igbinary version pin, imagick build method, oauth, xdebug) live in each
# {version}/base/Dockerfile.
#
# This stage is referenced as the 'common-php-ext' Bake named context.
# It is cached in GitHub Actions (type=gha) but never pushed to Docker Hub.
ARG PHP_VERSION=8.3
FROM php:${PHP_VERSION}-apache AS php-ext-common

#== System Environments
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
RUN apt-get update && apt-get upgrade -y \
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
    && rm -rf /var/lib/apt/lists/*

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
RUN dpkg -i /tmp/code-server.deb \
    || { apt-get update && apt-get install -y -f --no-install-recommends \
         && rm -rf /var/lib/apt/lists/*; dpkg -i /tmp/code-server.deb; } \
    && rm /tmp/code-server.deb

# Install Composer 2.x (default 2.3.10; PHP 8.3 overrides to 2.7.7 via self-update)
# and legacy Composer 1.x for projects that require it.
# 'composer2' and 'composer1' are bash aliases set after USER switch below.
RUN curl -fsSL https://getcomposer.org/installer \
      | php -- --install-dir=/usr/local/bin --filename=composer  --version=2.3.10 \
    && curl -fsSL https://getcomposer.org/installer \
      | php -- --install-dir=/usr/local/bin --filename=composer-1 --version=1.10.16

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

# Bash aliases for Composer versions.  The binaries are installed as root above;
# aliases are set here (as the app user) to keep them in ~/.bashrc.
RUN composer update --working-dir=/drush/drush8 \
    && echo "alias composer2=/usr/local/bin/composer" >> ~/.bashrc \
    && echo "alias composer1=/usr/local/bin/composer-1" >> ~/.bashrc \
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
