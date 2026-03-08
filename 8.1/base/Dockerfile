# syntax=docker/dockerfile:1
# ─── PHP 8.1 base final image ─────────────────────────────────────────────────
# Extends the 'common-php-ext' intermediate (from base/Dockerfile) built with
# PHP_VERSION=8.1. Contains ONLY PHP 8.1 specific differences:
#   - libavif-dev + libpcre2-dev
#   - gd configure flags (with avif)
#   - PECL: igbinary 3.2.12, imagick via pecl
FROM common-php-ext AS final

# Switch to root for version-specific installation
ARG DEBIAN_FRONTEND=noninteractive
USER root

# PHP 8.1+ specific packages: libavif-dev (avif gd support) and libpcre2-dev
# Retry up to 3 times to handle transient apt mirror/network failures (e.g. connection
# resets mid-download). seq generates the sequence so i takes values 1, 2, 3 in turn.
RUN for i in $(seq 1 3); do \
      apt-get update \
        && apt-get install -y --no-install-recommends \
          libavif-dev \
          libpcre2-dev \
        && break \
      || { [ "$i" -lt 3 ] && sleep 5; }; \
    done \
    && rm -rf /var/lib/apt/lists/*

# Configure gd with avif support (PHP 8.1+)
RUN docker-php-ext-configure gd --with-avif --with-freetype --with-jpeg --with-webp

RUN docker-php-ext-install -j$(nproc) gd

# PHP 8.1 PECL: igbinary 3.2.12, imagick via pecl (no oauth, no xdebug)
RUN pecl install -o -f \
      igbinary-3.2.12 \
      imagick-3.7.0

RUN docker-php-ext-enable gd igbinary imagick

USER ${USER}

# Run drush11 composer update (deferred from common stage; symfony/http-kernel
# 6.2.4 in base/drush/drush11/composer.json requires PHP >=8.1, so it must
# run in the per-version stage, not the shared php-ext-common stage).
RUN composer update --working-dir=/drush/drush11
