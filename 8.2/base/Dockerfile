# syntax=docker/dockerfile:1
# ─── PHP 8.2 base final image ─────────────────────────────────────────────────
# Extends the 'common-php-ext' intermediate (from base/Dockerfile) built with
# PHP_VERSION=8.2. Contains ONLY PHP 8.2 specific differences:
#   - libavif-dev + libpcre2-dev
#   - gd configure flags (with avif)
#   - PECL: igbinary 3.2.12, imagick via pecl
FROM common-php-ext AS final

# Switch to root for version-specific installation
ARG DEBIAN_FRONTEND=noninteractive
USER root

# PHP 8.2 specific packages: libavif-dev (avif gd support) and libpcre2-dev
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      libavif-dev \
      libpcre2-dev \
    || (sleep 5 && apt-get update && apt-get install -y --no-install-recommends --fix-missing \
      libavif-dev \
      libpcre2-dev) \
    && rm -rf /var/lib/apt/lists/*

# Configure gd with avif support (PHP 8.1+)
RUN docker-php-ext-configure gd --with-avif --with-freetype --with-jpeg --with-webp

RUN docker-php-ext-install -j$(nproc) gd

# PHP 8.2 PECL: igbinary 3.2.12, imagick via pecl (no oauth, no xdebug)
RUN pecl install -o -f \
      igbinary-3.2.12 \
      imagick-3.7.0

RUN docker-php-ext-enable gd igbinary imagick

USER ${USER}
