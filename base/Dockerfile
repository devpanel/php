# syntax=docker/dockerfile:1
ARG PHP_VERSION

# ─── Stage 1: Version-independent artifact downloader ─────────────────────
# Uses a fixed base image (debian:bookworm-slim) whose layers are completely
# independent of PHP_VERSION.  BuildKit can reuse these cached layers across
# all PHP version builds, so large binaries (code-server, libsodium) are only
# downloaded once regardless of how many PHP versions are being built.
FROM debian:bookworm-slim AS downloader

ARG CODESERVER_MAJOR_VERSION=4
ARG CODESERVER_PINNED_HASH_VERSION=4.99.4
ARG CODESERVER_VERSION=$CODESERVER_PINNED_HASH_VERSION
ARG CODESERVER_DEB_SHA256_AMD64=74c107b33643ed11223263b86431530fbc9c9f7c8202997579a6f0c41b4cb102
ARG CODESERVER_DEB_SHA256_ARM64=ae12d6300736dd742de3f5aef1b80c996c4b164ed385992e5de9d55f1e2077c3

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl \
      ca-certificates \
      jq \
    && rm -rf /var/lib/apt/lists/*

# Download libsodium source (pinned release, identical for every PHP version)
RUN mkdir -p /tmp/libsodium \
    && curl -sL https://github.com/jedisct1/libsodium/archive/1.0.18-RELEASE.tar.gz \
       | tar xzf - -C /tmp/libsodium

# Download code-server deb (identical binary for every PHP version).
# jq is used for the optional dynamic-version resolution so that this stage
# does not depend on php-cli (keeping it PHP-version-independent).
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
    CODESERVER_VERSION="$(printf '%s' "$RELEASES_JSON" | \
      jq -r --arg major "$CODESERVER_MAJOR_VERSION" \
      '[.[] | select(.draft == false and .prerelease == false) | .tag_name | ltrimstr("v") | select(test("^" + $major + "\\.[0-9]+\\.[0-9]+([-+].*)?$"))] | first // empty')" \
      || { echo "Unable to resolve code-server major $CODESERVER_MAJOR_VERSION from GitHub releases" >&2; exit 1; }; \
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

# ─── Stage 2: PHP runtime with extensions ─────────────────────────────────
# Contains system packages, PHP extension compilation and libsodium. These
# layers change only when the PHP base image or extension configuration changes,
# so they form a stable cache layer that does not need to be rebuilt when
# higher-level tools (Composer, WP-CLI, Drush, etc.) are updated.
FROM php:${PHP_VERSION}-apache AS php-ext

# Re-declare so PHP_VERSION is available after FROM.
# Docker ARG scoping rule: an ARG declared before FROM applies only to the FROM
# instruction itself. It must be re-declared here to be accessible in
# subsequent RUN/COPY/ENV instructions within this stage.
ARG PHP_VERSION

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
ENV GIT_BRANCH=master

ENV CODES_PORT=8080
ENV CODES_WORKING_DIR=$APP_ROOT
ENV CODES_USER_DATA_DIR=$APP_ROOT/.vscode
ENV CODES_ENABLE=yes

# Install polymorphing if needed
RUN apt -y update && apt -y upgrade;
RUN if [ ! -z "$POLYVER_CUSTOMER_KEY" ]; then \
  curl -s https://repo.polyverse.io/cli | sh -s install cDDwaMuYf7BtSOt4jfJGl3TsA; \
  if [ $? -eq 0 ]; then \
  curl https://repo.polyverse.io/cli | bash -s replace-installed-elf; \
  fi; fi;

# Install dependencies.
# - libavif-dev required for avif gd support from PHP 8.1+
# - libpcre2-dev replaces libpcre3/libpcre3-dev from PHP 8.0+
RUN set -e; \
    AVIF_PKG=""; \
    if dpkg --compare-versions "$PHP_VERSION" ge "8.1"; then \
      AVIF_PKG="libavif-dev"; \
    fi; \
    if dpkg --compare-versions "$PHP_VERSION" ge "8.0"; then \
      PCRE_PKG="libpcre2-dev"; \
    else \
      PCRE_PKG="libpcre3 libpcre3-dev"; \
    fi; \
    apt-get install -y --no-install-recommends \
      apt-utils \
      sendmail-bin \
      sendmail \
      sudo \
      $AVIF_PKG \
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
      $PCRE_PKG \
      libssl-dev \
      zlib1g-dev \
      zip unzip \
      git \
      rsync \
      ssh \
      default-mysql-client \
    && rm -rf /var/lib/apt/lists/*

# Configure the gd library.
# PHP 8.1+ uses --with-avif and the shorter flag syntax; earlier versions use
# the explicit path form and do not support avif.
RUN if dpkg --compare-versions "$PHP_VERSION" ge "8.1"; then \
      docker-php-ext-configure gd --with-avif --with-freetype --with-jpeg --with-webp; \
    else \
      docker-php-ext-configure gd --with-freetype=/usr/include/ --with-jpeg=/usr/include/ --with-webp=/usr/include/; \
    fi
RUN docker-php-ext-configure \
  opcache --enable-opcache

# Install required PHP extensions
RUN docker-php-ext-install -j$(nproc) \
  bcmath \
  bz2 \
  calendar \
  exif \
  gd \
  gettext \
  gmp \
  intl \
  mysqli \
  opcache \
  pdo_mysql \
  pspell \
  shmop \
  soap \
  sockets \
  sysvmsg \
  sysvsem \
  sysvshm \
  tidy \
  xsl \
  zip \
  pcntl

# Install PECL extensions.
# - igbinary: pinned to 3.2.12 for PHP < 8.3, latest for PHP 8.3+
# - imagick: installed via pecl for PHP < 8.3; built from source for PHP 8.3+
#   because the pecl package does not yet support PHP 8.3
# - oauth: pecl extension only available for PHP 7.4; PHP 8.0+ does not use it
RUN set -e; \
    if dpkg --compare-versions "$PHP_VERSION" ge "8.3"; then \
      IGBINARY_PKG="igbinary"; \
    else \
      IGBINARY_PKG="igbinary-3.2.12"; \
    fi; \
    if dpkg --compare-versions "$PHP_VERSION" lt "8.3"; then \
      pecl install -o -f \
        $IGBINARY_PKG \
        imagick-3.7.0 \
        redis-5.3.7 \
        yaml-2.2.2 \
        memcached-3.2.0; \
    else \
      pecl install -o -f \
        $IGBINARY_PKG \
        redis-5.3.7 \
        yaml-2.2.2 \
        memcached-3.2.0; \
    fi; \
    # oauth PECL extension only exists for PHP 7.4
    if dpkg --compare-versions "$PHP_VERSION" lt "8.0"; then \
      pecl install -o -f oauth-2.0.7; \
    fi

# Build imagick from source for PHP 8.3+ (pecl package not yet compatible)
RUN if dpkg --compare-versions "$PHP_VERSION" ge "8.3"; then \
      curl -L -o /tmp/imagick.tar.gz https://github.com/Imagick/imagick/archive/7088edc353f53c4bc644573a79cdcd67a726ae16.tar.gz \
      && tar --strip-components=1 -xf /tmp/imagick.tar.gz \
      && phpize \
      && ./configure \
      && make \
      && make install \
      && echo "extension=imagick.so" > /usr/local/etc/php/conf.d/ext-imagick.ini \
      && rm -rf /tmp/*; \
    fi

# Install libsodium (source pre-downloaded in the 'downloader' stage)
COPY --from=downloader /tmp/libsodium /tmp/libsodium
RUN rm -f /usr/local/etc/php/conf.d/*sodium.ini \
  && rm -f /usr/local/lib/php/extensions/*/*sodium.so \
  && apt-get remove libsodium* -y  \
  && cd /tmp/libsodium/libsodium-1.0.18-RELEASE/ \
  && ./configure \
  && make && make check \
  && make install  \
  && cd / \
  && rm -rf /tmp/libsodium  \
  && pecl install -o -f libsodium

# Enable PHP extensions; oauth is a pecl extension only on PHP 7.4
RUN docker-php-ext-enable \
  bcmath \
  bz2 \
  calendar \
  exif \
  gd \
  gettext \
  gmp \
  igbinary \
  imagick \
  intl \
  mysqli \
  opcache \
  pdo_mysql \
  pspell \
  redis \
  shmop \
  soap \
  sockets \
  sodium \
  sysvmsg \
  sysvsem \
  sysvshm \
  tidy \
  xsl \
  yaml \
  zip \
  pcntl \
  memcached
RUN if dpkg --compare-versions "$PHP_VERSION" lt "8.0"; then \
      docker-php-ext-enable oauth; \
    fi

RUN groupadd -g ${GID} ${GROUP} \
    && useradd --system --shell /bin/bash --uid ${UID} --gid ${GROUP}  --create-home --home-dir /home/${USER} ${USER} \
    && adduser ${USER} www-data \
    && apt install -y sudo \
    && usermod -aG sudo ${USER} \
    && echo "www    ALL=(ALL:ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN mkdir -p ${APP_ROOT} \
    && chown -R ${UID}:${GID} ${APP_ROOT}

#== Enable mode_rewrite by default
RUN a2enmod rewrite remoteip headers

# ─── Stage 3: Final image with application-level tools ────────────────────
# Inherits the stable PHP + extensions layers from php-ext and adds tools that
# change more frequently: code-server, Composer, WP-CLI, Drush, BEE, etc.
# Rebuilding this stage does not invalidate the php-ext layer cache.
FROM php-ext AS final

# PHP_VERSION must be re-declared in each stage that uses it (Docker ARG scoping).
ARG PHP_VERSION

#== Install Codeserver (deb pre-downloaded in the 'downloader' stage)
COPY --from=downloader /tmp/code-server.deb /tmp/code-server.deb
RUN dpkg -i /tmp/code-server.deb || { apt-get update && apt-get install -y -f --no-install-recommends; rm -rf /var/lib/apt/lists/*; dpkg -i /tmp/code-server.deb; }; \
    rm -f /tmp/code-server.deb

#== Enable xdebug (PHP 8.3+ only)
RUN if dpkg --compare-versions "$PHP_VERSION" ge "8.3"; then \
      pecl install xdebug; \
    fi

#== Install Composer
# PHP 8.3+ uses composer 2.7.7; earlier versions use 2.3.10.
# Both `composer` and `composer2` are pinned to the same version so that
# scripts referencing either alias get consistent behaviour.
RUN set -e; \
    if dpkg --compare-versions "$PHP_VERSION" ge "8.3"; then \
      COMPOSER_VERSION="2.7.7"; \
    else \
      COMPOSER_VERSION="2.3.10"; \
    fi; \
    curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer  --version=$COMPOSER_VERSION \
    && curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer2 --version=$COMPOSER_VERSION \
    && curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer1 --version=1.10.16

#== Install DevPanel CLI client
COPY bin/devpanel /usr/local/bin/devpanel
RUN chmod +x /usr/local/bin/devpanel \
  && devpanel version

#== Install Wordpress CLI
# PHP 7.4 ships with WP-CLI 2.4.0; PHP 8.x uses 2.9.0
ARG WP_CLI_VERSION
RUN set -e; \
    if [ -z "$WP_CLI_VERSION" ]; then \
      if dpkg --compare-versions "$PHP_VERSION" ge "8.0"; then \
        WP_CLI_VERSION="2.9.0"; \
      else \
        WP_CLI_VERSION="2.4.0"; \
      fi; \
    fi; \
    curl -LO https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar \
    && chmod +x wp-cli-${WP_CLI_VERSION}.phar \
    && mv wp-cli-${WP_CLI_VERSION}.phar /usr/local/bin/wp

WORKDIR ${APP_ROOT}
COPY drush /drush
RUN mkdir -p /home/$USER/.config/code-server \
    && chown -R $USER:$USER /home/$USER/.config/code-server

USER ${USER}

RUN touch /home/$USER/.config/code-server/config.yaml
RUN sudo chown -R ${USER} /drush

#== Install Drush
ARG DRUSH_VERSION=8
# drush7 is only available for PHP 7.4
RUN if dpkg --compare-versions "$PHP_VERSION" lt "8.0"; then \
      composer update --working-dir=/drush/drush7 \
      && echo "alias drush7=/drush/drush7/vendor/bin/drush" >> ~/.bashrc; \
    fi
RUN composer update --working-dir=/drush/drush8 \
  && echo "alias drush8=/drush/drush8/vendor/bin/drush" >> ~/.bashrc
RUN  composer update --working-dir=/drush/drush9 \
  && echo "alias drush9=/drush/drush9/vendor/bin/drush" >> ~/.bashrc
RUN  composer update --working-dir=/drush/drush10 \
  && echo "alias drush10=/drush/drush10/vendor/bin/drush" >> ~/.bashrc
RUN  composer update --working-dir=/drush/drush11 \
  && echo "alias drush11=/drush/drush11/vendor/bin/drush" >> ~/.bashrc

#== Install Drush backdrop extension
RUN wget https://github.com/backdrop-contrib/backdrop-drush-extension/archive/refs/heads/1.x-1.x.zip \
  && unzip 1.x-1.x.zip -d /drush/drush${DRUSH_VERSION}/vendor/drush/drush/commands/backdrop \
  && /drush/drush${DRUSH_VERSION}/vendor/bin/drush cc drush


#== Install BEE CLI client
RUN sudo mkdir /bee && sudo git clone https://github.com/backdrop-contrib/bee.git /bee
RUN sudo chmod +x /bee/bee.php \
  && sudo ln -s /bee/bee.php /usr/bin/bee


RUN bash ~/.bashrc
RUN sudo ln -s /drush/drush${DRUSH_VERSION}/vendor/bin/drush /usr/bin/drush

#== Start apache.
COPY templates /templates
COPY scripts /scripts
# PHP 8.3+ empties APP_ROOT to keep the container smaller
RUN if dpkg --compare-versions "$PHP_VERSION" ge "8.3"; then \
      sudo rm -rf ${APP_ROOT} && sudo mkdir -p ${APP_ROOT}; \
    fi

CMD ["sudo", "-E", "/bin/bash", "/scripts/apache-start.sh" ]
