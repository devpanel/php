# syntax=docker/dockerfile:1
# ─── PHP 8.0 base final image ─────────────────────────────────────────────────
# Extends the 'common-php-ext' intermediate (from base/Dockerfile) built with
# PHP_VERSION=8.0. Contains ONLY PHP 8.0 specific differences:
#   - libpcre2-dev (no libavif-dev) + gd/imagick build libs: installed, used, removed
#   - gd configure flags (no avif)
#   - PECL: igbinary 3.2.12, imagick via pecl
FROM common-php-ext AS final

# Switch to root for version-specific installation
ARG DEBIAN_FRONTEND=noninteractive
USER root

# Install dev libraries needed to build gd and imagick for PHP 8.0, build the
# extensions, then remove the dev libraries and their automatically-added
# dependencies that are not needed at runtime.
# libpcre2-dev provides PCRE2 headers for the regex engine used by gd on Debian 11.
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
          libmagickwand-dev \
          libmagickcore-dev \
          libpcre2-dev \
        && break \
      || { [ "$i" -lt 3 ] && sleep 5; }; \
    done \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j$(nproc) gd \
    && pecl install -o -f \
        igbinary-3.2.12 \
        imagick-3.7.0 \
    && docker-php-ext-enable gd igbinary imagick \
    && apt-mark auto '.*' > /dev/null \
    && echo "$savedAptMark" | xargs apt-mark manual \
    && { find /usr/local/lib/php/extensions -name '*.so' \
            -exec ldd '{}' ';' 2>/dev/null \
            | awk '/=>/ { print $(NF-1) }' \
            | sort -u \
            | xargs -r dpkg-query --search 2>/dev/null \
            | cut -d: -f1 \
            | sort -u \
            | xargs -r apt-mark manual; } || true \
    && apt-get purge -y --auto-remove \
        -o APT::AutoRemove::RecommendsImportant=false \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/apt/apt.conf.d/01dpkg-no-pty

USER ${USER}
