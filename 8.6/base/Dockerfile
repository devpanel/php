# syntax=docker/dockerfile:1
# ─── PHP 8.6 base final image ─────────────────────────────────────────────────
# Extends the 'common-php-ext' intermediate (from base/Dockerfile) built with
# PHP_VERSION=8.6 (official php:8.6-apache, PHP 8.6.0 GA). Contains ONLY the
# differences from PHP 8.5 that the shared stage does not already handle:
#   - libonig-dev: mbstring is built into php:8.5-apache and absent from 8.6
#   - libavif-dev + libpcre2-dev (+ gd build libs) installed, used, removed
#   - gd configure flags (with avif)
#   - igbinary, Xdebug, and Imagick from the unreleased commits that support
#     PHP 8.6. Imagick also replaces removed zval_dtor() calls.
#   - Composer override (common installs 2.3.10)
# pspell stays omitted (removed from PHP in 8.4). OPcache is part of the
# binary since 8.5 and is handled in the shared stage. PECL is installed by
# the shared stage when the official image does not ship it.
FROM common-php-ext AS final

# Switch to root for version-specific installation
ARG DEBIAN_FRONTEND=noninteractive
USER root

# Install dev libraries needed to build gd, mbstring, and imagick for PHP 8.6,
# build the extensions, then remove the dev libraries and their
# automatically-added dependencies that are not needed at runtime.
# libonig-dev builds mbstring, which the official 8.6 image no longer includes.
# libavif-dev enables AVIF image support in gd (PHP 8.1+).
# libmagickwand-dev and libmagickcore-dev are required to build imagick.
# Released igbinary 3.2.16, Xdebug 3.5.3, and Imagick 3.8.1 do not compile on
# PHP 8.6. Build the commits that do. Imagick master still calls removed
# zval_dtor(), so those calls are rewritten to zval_ptr_dtor_nogc().
# Xdebug 3.6 drops PHP 8.0 and 8.1, so it stays in this file.
# See base/Dockerfile for the full explanation of the apt-mark + ldd strategy.
ARG IGBINARY_COMMIT=2b1f5d62e3037b07c2a46499ac32091cdb41fb40
ARG IGBINARY_SHA256=1664c973d836ae7f0dfa92dbbc04504d506f8caf7c14db27e245646aaaceeab8
ARG XDEBUG_COMMIT=5e19866c1766e38c527f9f94faa170370dc4209f
ARG XDEBUG_SHA256=a11d140cb67da8920df0a063c4d77b893b71b0195bb96f871c5f5915e0544ec8
ARG IMAGICK_COMMIT=55ed2e9fda264395636a2e27e51f31673f5566ab
ARG IMAGICK_SHA256=81a24f34334cb620ea16ed563afdc3b61b60ab321f2d817dd0412a8f20ddedf6
RUN echo 'Dpkg::Use-Pty "0";' > /etc/apt/apt.conf.d/01dpkg-no-pty \
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
        && break \
      || { [ "$i" -lt 3 ] && sleep 5; }; \
    done \
    && docker-php-ext-configure gd --with-avif --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j$(nproc) gd mbstring \
    && curl -fsSL --retry 5 --retry-all-errors --connect-timeout 10 \
         -o /tmp/igbinary.tar.gz \
         "https://github.com/igbinary/igbinary/archive/${IGBINARY_COMMIT}.tar.gz" \
    && echo "${IGBINARY_SHA256}  /tmp/igbinary.tar.gz" > /tmp/igbinary.tar.gz.sha256 \
    && sha256sum -c /tmp/igbinary.tar.gz.sha256 \
    && tar -xzf /tmp/igbinary.tar.gz -C /tmp \
    && ( cd "/tmp/igbinary-${IGBINARY_COMMIT}" \
         && phpize && ./configure && make -j"$(nproc)" && make install ) \
    && rm -rf /tmp/igbinary.tar.gz /tmp/igbinary.tar.gz.sha256 \
         "/tmp/igbinary-${IGBINARY_COMMIT}" \
    && curl -fsSL --retry 5 --retry-all-errors --connect-timeout 10 \
         -o /tmp/xdebug.tar.gz \
         "https://github.com/xdebug/xdebug/archive/${XDEBUG_COMMIT}.tar.gz" \
    && echo "${XDEBUG_SHA256}  /tmp/xdebug.tar.gz" > /tmp/xdebug.tar.gz.sha256 \
    && sha256sum -c /tmp/xdebug.tar.gz.sha256 \
    && tar -xzf /tmp/xdebug.tar.gz -C /tmp \
    && ( cd "/tmp/xdebug-${XDEBUG_COMMIT}" \
         && phpize && ./configure && make -j"$(nproc)" && make install ) \
    && rm -rf /tmp/xdebug.tar.gz /tmp/xdebug.tar.gz.sha256 \
         "/tmp/xdebug-${XDEBUG_COMMIT}" \
    && curl -fsSL --retry 5 --retry-all-errors --connect-timeout 10 \
         -o /tmp/imagick.tar.gz \
         "https://github.com/Imagick/imagick/archive/${IMAGICK_COMMIT}.tar.gz" \
    && echo "${IMAGICK_SHA256}  /tmp/imagick.tar.gz" > /tmp/imagick.tar.gz.sha256 \
    && sha256sum -c /tmp/imagick.tar.gz.sha256 \
    && tar -xzf /tmp/imagick.tar.gz -C /tmp \
    && ( cd "/tmp/imagick-${IMAGICK_COMMIT}" \
         && sed -i 's/zval_dtor(/zval_ptr_dtor_nogc(/g' ./*.c ./*.h \
         && phpize && ./configure && make -j"$(nproc)" && make install ) \
    && rm -rf /tmp/imagick.tar.gz /tmp/imagick.tar.gz.sha256 \
         "/tmp/imagick-${IMAGICK_COMMIT}" \
    && docker-php-ext-enable gd igbinary imagick mbstring xdebug \
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

USER ${USER}
