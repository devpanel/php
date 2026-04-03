# syntax=docker/dockerfile:1
# ─── PHP 8.5 base final image ─────────────────────────────────────────────────
# Extends the 'common-php-ext' intermediate (from base/Dockerfile) built with
# PHP_VERSION=8.5. Contains ONLY PHP 8.5 specific differences:
#   - libavif-dev + libpcre2-dev (+ gd build libs) installed, used, removed
#   - gd configure flags (with avif)
#   - PECL: igbinary latest (no version pin), imagick latest, xdebug
#   - Composer override (common installs 2.3.10)
FROM common-php-ext AS final

# Switch to root for version-specific installation
ARG DEBIAN_FRONTEND=noninteractive
USER root

# Install dev libraries needed to build gd and imagick for PHP 8.5,
# build the extensions, then remove the dev libraries and their
# automatically-added dependencies that are not needed at runtime.
# libavif-dev enables AVIF image support in gd (PHP 8.1+).
# libmagickwand-dev and libmagickcore-dev are required to build imagick.
# imagick is installed without a version pin to pick up the latest release with
# PHP 8.5 API support (imagick 3.8.x does not support PHP 8.4+).
# See base/Dockerfile for the full explanation of the apt-mark + ldd strategy.
RUN echo 'Dpkg::Use-Pty "0";' > /etc/apt/apt.conf.d/01dpkg-no-pty \
    && savedAptMark="$(apt-mark showmanual)" \
    && for i in $(seq 1 3); do \
      apt-get update \
        && apt-get install -y --no-install-recommends \
          libjpeg62-turbo-dev \
          libpng-dev \
          libwebp-dev \
          libfreetype6-dev \
          libavif-dev \
          libpcre2-dev \
          libmagickwand-dev \
          libmagickcore-dev \
        && break \
      || { [ "$i" -lt 3 ] && sleep 5; }; \
    done \
    && docker-php-ext-configure gd --with-avif --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j$(nproc) gd \
    && pecl install -o -f \
        igbinary \
        imagick \
        xdebug \
    && docker-php-ext-enable gd igbinary imagick xdebug \
    && apt-mark auto '.*' > /dev/null \
    && echo "$savedAptMark" | xargs -r apt-mark manual \
    && { find /usr/local/lib/php/extensions -name '*.so' \
            -exec ldd '{}' ';' 2>/dev/null \
            | awk '/=>/ { print $(NF-1) }' \
            | grep '^/' \
            | sort -u \
            | while IFS= read -r lib; do dpkg-query --search "$(realpath "$lib" 2>/dev/null || echo "$lib")" 2>/dev/null; done \
            | cut -d: -f1 \
            | sort -u \
            | xargs -r apt-mark manual; } || true \
    && apt-get purge -y --auto-remove \
        -o APT::AutoRemove::RecommendsImportant=false \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/apt/apt.conf.d/01dpkg-no-pty

# Override Composer with PHP 8.5 version using self-update
RUN composer self-update

USER ${USER}

# Overlay version-specific Drush files. Docker COPY merges so common
# drush8/9/10/11 are preserved.
COPY --chown=${USER}:${GROUP} drush /drush

RUN set -e; for drush_dir in /drush/drush*; do \
  drush_name=$(basename "$drush_dir"); \
  composer update --working-dir="$drush_dir"; \
  echo "alias $drush_name=$drush_dir/vendor/bin/drush" >> ~/.bashrc; \
  done

RUN wget https://github.com/backdrop-contrib/backdrop-drush-extension/archive/refs/heads/1.x-1.x.zip \
    && unzip 1.x-1.x.zip -d "/drush/drush${DRUSH_VERSION}/vendor/drush/drush/commands/backdrop" \
    && "/drush/drush${DRUSH_VERSION}/vendor/bin/drush" cc drush
