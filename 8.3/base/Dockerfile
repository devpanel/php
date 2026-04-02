# syntax=docker/dockerfile:1
# ─── PHP 8.3 base final image ─────────────────────────────────────────────────
# Extends the 'common-php-ext' intermediate (from base/Dockerfile) built with
# PHP_VERSION=8.3. Contains ONLY PHP 8.3 specific differences:
#   - libavif-dev + libpcre2-dev (+ gd build libs) installed, used, removed
#   - libmagickwand-dev + libmagickcore-dev for imagick: installed, used, removed
#   - libpspell-dev for pspell: installed, used, removed
#   - gd configure flags (with avif)
#   - PECL: igbinary latest (no version pin), imagick latest, xdebug
#   - Composer 2.7.7 override (common installs 2.3.10)
FROM common-php-ext AS final

# Switch to root for version-specific installation
ARG DEBIAN_FRONTEND=noninteractive
USER root

# Install dev libraries needed to build gd, imagick, and pspell for PHP 8.3,
# build the extensions, then remove the dev libraries and their
# automatically-added dependencies that are not needed at runtime.
# libavif-dev enables AVIF image support in gd (PHP 8.1+).
# libmagickwand-dev and libmagickcore-dev are required to build imagick.
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
          libpspell-dev \
        && break \
      || { [ "$i" -lt 3 ] && sleep 5; }; \
    done \
    && docker-php-ext-configure gd --with-avif --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j$(nproc) gd pspell \
    && pecl install -o -f \
        igbinary \
        imagick \
        xdebug \
    && docker-php-ext-enable gd igbinary imagick pspell xdebug \
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

# Override Composer with PHP 8.3 version (2.7.7) using self-update
RUN composer self-update 2.7.7

USER ${USER}

