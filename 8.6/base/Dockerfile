# syntax=docker/dockerfile:1
# ─── PHP 8.6 base final image ─────────────────────────────────────────────────
# Extends the 'common-php-ext' intermediate (from base/Dockerfile) built with
# PHP_VERSION=8.6 (official php:8.6-apache, PHP 8.6.0 GA). Contains ONLY the
# differences from PHP 8.5 that the shared stage does not already handle:
#   - libonig-dev: mbstring is enabled by default in php:8.5-apache but not in php:8.6-apache
#   - libavif-dev + libpcre2-dev (+ gd build libs) installed, used, removed
#   - gd configure flags (with avif)
#   - third-party extensions via PIE (php:8.6-apache does not ship pecl):
#     redis, yaml, memcached, igbinary, Xdebug, and Imagick
#   - Composer override (common installs 2.3.10)
# pspell stays omitted (removed from PHP in 8.4). OPcache is part of the
# binary since 8.5 and is handled in the shared stage. Sodium is bundled and
# rebuilt in the shared stage; Packagist has no PIE package for it.

#== PIE binary (build-time installs and runtime copy)
# Pinned PIE image; digest is the multi-arch index of ghcr.io/php/pie:1.5.5-bin.
ARG PIE_VERSION=1.5.5
ARG PIE_IMAGE_DIGEST=sha256:3fca03c16df842d02b654dc382db3756058d9c128064f57cace14f8728779ce9
FROM ghcr.io/php/pie:${PIE_VERSION}-bin@${PIE_IMAGE_DIGEST} AS pie

FROM common-php-ext AS final

# Switch to root for version-specific installation
ARG DEBIAN_FRONTEND=noninteractive
USER root

# Install dev libraries needed to build gd, mbstring, and imagick for PHP 8.6,
# build the extensions, then remove the dev libraries and their
# automatically-added dependencies that are not needed at runtime.
# libonig-dev builds mbstring, which the official 8.6 image does not enable by default.
# libavif-dev enables AVIF image support in gd (PHP 8.1+).
# libmagickwand-dev and libmagickcore-dev are required to build imagick.
# Released PECL redis 6.3.0, yaml 2.3.0, memcached 3.4.0, igbinary 3.2.16,
# Xdebug 3.5.3, and Imagick 3.8.1 do not compile on PHP 8.6. PIE installs the
# commits that do, plus Xdebug 3.6.0alpha1 (3.6 drops PHP 8.0 and 8.1, so it
# stays in this file). Imagick master still calls removed zval_dtor(); that
# one install maps the call to zval_ptr_dtor_nogc() with a compiler macro.
# During this build PIE is bind-mounted from its binary image (ghcr.io/php/pie:1.5.5-bin).
# The same pinned binary is copied into the runtime layer at the end of this
# file so users can run `pie install` inside containers.
# See base/Dockerfile for the full explanation of the apt-mark + ldd strategy.
ARG PHPREDIS_COMMIT=a6ce1e60b3e81ce3b25174aa5aaefd5590dc64fd
ARG YAML_COMMIT=a7a3b8680b8fbf0895fd63371a0ffc1305b1a5b8
ARG MEMCACHED_COMMIT=0b52d3657140750fa0eddd20cdbfc6edc8fbdadd
ARG IGBINARY_COMMIT=2b1f5d62e3037b07c2a46499ac32091cdb41fb40
ARG XDEBUG_VERSION=3.6.0alpha1
ARG IMAGICK_COMMIT=55ed2e9fda264395636a2e27e51f31673f5566ab
RUN --mount=type=bind,from=pie,source=/pie,target=/usr/local/bin/pie \
    echo 'Dpkg::Use-Pty "0";' > /etc/apt/apt.conf.d/01dpkg-no-pty \
    && savedAptMark="$(apt-mark showmanual)" \
    && for i in $(seq 1 3); do \
      apt-get update \
        && apt-get install -y --no-install-recommends \
          libjpeg62-turbo-dev \
          libpng-dev \
          libwebp-dev \
          libfreetype6-dev \
          libonig-dev \
          libavif-dev \
          libpcre2-dev \
          libmagickwand-dev \
          libmagickcore-dev \
          libyaml-dev \
          libmemcached-dev \
          zlib1g-dev \
          libssl-dev \
        && break \
      || { [ "$i" -lt 3 ] && sleep 5; }; \
    done \
    && docker-php-ext-configure gd --with-avif --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j$(nproc) gd mbstring \
    && pie install -n --no-cache \
         "phpredis/phpredis:dev-develop#${PHPREDIS_COMMIT}" \
         "pecl/yaml:dev-php7#${YAML_COMMIT}" \
         "php-memcached/php-memcached:dev-master#${MEMCACHED_COMMIT}" \
         "igbinary/igbinary:dev-master#${IGBINARY_COMMIT}" \
         "xdebug/xdebug:${XDEBUG_VERSION}" \
    && CFLAGS="-Dzval_dtor=zval_ptr_dtor_nogc" \
       pie install -n --no-cache \
         "imagick/imagick:dev-master#${IMAGICK_COMMIT}" \
    && rm -rf /root/.pie \
    && docker-php-ext-enable gd mbstring \
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
            | xargs -r apt-mark manual; } \
    && apt-get purge -y --auto-remove \
        -o APT::AutoRemove::RecommendsImportant=false \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/apt/apt.conf.d/01dpkg-no-pty

# Install psql 18x
RUN echo 'Dpkg::Use-Pty "0";' > /etc/apt/apt.conf.d/01dpkg-no-pty \
    && for i in $(seq 1 3); do \
      apt-get update \
        && apt-get install -y --no-install-recommends postgresql-common \
        && break \
      || { [ "$i" -lt 3 ] && sleep 5; }; \
    done \
    && /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y \
    && for i in $(seq 1 3); do \
      apt-get update \
        && apt-get install -y --no-install-recommends postgresql-client-18 \
        && break \
      || { [ "$i" -lt 3 ] && sleep 5; }; \
    done \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/apt/apt.conf.d/01dpkg-no-pty

# Override Composer with PHP 8.6 version using self-update
RUN composer self-update

#== Install PIE in the runtime image
# Same pinned binary as the build-time mount above (the 'pie' stage).
COPY --from=pie --chown=root:root --chmod=0755 /pie /usr/local/bin/pie

USER ${USER}
