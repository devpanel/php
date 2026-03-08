# syntax=docker/dockerfile:1
# ─── PHP 8.0 base final image ─────────────────────────────────────────────────
# Extends the 'common-php-ext' intermediate (from base/Dockerfile) built with
# PHP_VERSION=8.0. Contains ONLY PHP 8.0 specific differences:
#   - libpcre2-dev (no libavif-dev)
#   - gd configure flags (no avif)
#   - PECL: igbinary 3.2.12, imagick via pecl
FROM common-php-ext AS final

# Switch to root for version-specific installation
ARG DEBIAN_FRONTEND=noninteractive
USER root

# PHP 8.0 (Debian 11) specific package: libpcre2-dev (no libavif-dev)
# Retry up to 3 times to handle transient apt mirror/network failures (e.g. connection
# resets mid-download). seq generates the sequence so i takes values 1, 2, 3 in turn.
RUN echo 'Dpkg::Use-Pty "0";' > /etc/apt/apt.conf.d/01dpkg-no-pty \
    && for i in $(seq 1 3); do \
      apt-get update \
        && apt-get install -y --no-install-recommends \
          libpcre2-dev \
        && break \
      || { [ "$i" -lt 3 ] && sleep 5; }; \
    done \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/apt/apt.conf.d/01dpkg-no-pty

# Configure gd (PHP 8.0: no avif support)
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp

RUN docker-php-ext-install -j$(nproc) gd

# PHP 8.0 PECL: igbinary 3.2.12, imagick via pecl (no oauth)
RUN pecl install -o -f \
      igbinary-3.2.12 \
      imagick-3.7.0

RUN docker-php-ext-enable gd igbinary imagick

USER ${USER}
