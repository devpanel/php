# syntax=docker/dockerfile:1
# ─── PHP 7.4 base final image ─────────────────────────────────────────────────
# Extends the 'common-php-ext' intermediate (from base/Dockerfile) built with
# PHP_VERSION=7.4. Contains ONLY PHP 7.4 specific differences:
#   - libpcre3/libpcre3-dev (no libavif-dev) + gd build libs: installed, used, removed
#   - libmagickwand-dev + libmagickcore-dev for imagick: installed, used, removed
#   - libpspell-dev for pspell: installed, used, removed
#   - gd configure flags (no avif)
#   - PECL: igbinary 3.2.12, imagick 3.8.1, oauth extension
#   - WP-CLI 2.4.0 override (common installs 2.9.0)
#   - drush7 (PHP 7.4 only)
#   - apache-start.sh override (extra WEB_ROOT substitution)
FROM common-php-ext AS final

# Switch to root for version-specific installation
ARG DEBIAN_FRONTEND=noninteractive
USER root

# Install dev libraries needed to build gd, imagick, and pspell for PHP 7.4,
# build the extensions, then remove the dev libraries and their
# automatically-added dependencies that are not needed at runtime.
# libpcre3-dev provides PCRE headers; libpcre3 is the runtime library and is
# kept (it is a shared-library dependency of the compiled extensions).
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
          libpcre3 \
          libpcre3-dev \
          libmagickwand-dev \
          libmagickcore-dev \
          libpspell-dev \
        && break \
      || { [ "$i" -lt 3 ] && sleep 5; }; \
    done \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j$(nproc) gd pspell \
    && pecl install -o -f \
        igbinary-3.2.12 \
        imagick-3.8.1 \
        oauth-2.0.7 \
    && docker-php-ext-enable gd igbinary imagick oauth pspell \
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

# Override WP-CLI with 7.4-specific version (2.4.0)
RUN rm -f /usr/local/bin/wp \
    && curl -LO https://github.com/wp-cli/wp-cli/releases/download/v2.4.0/wp-cli-2.4.0.phar \
    && chmod +x wp-cli-2.4.0.phar \
    && mv wp-cli-2.4.0.phar /usr/local/bin/wp

USER ${USER}

# Overlay version-specific Drush files. Docker COPY merges so common
# drush8/9/10/11 are preserved.
COPY drush /drush

RUN set -e; for drush_dir in /drush/drush*; do \
  drush_name=$(basename "$drush_dir"); \
  composer update --working-dir="$drush_dir"; \
  echo "alias $drush_name=$drush_dir/vendor/bin/drush" >> ~/.bashrc; \
  done

RUN wget https://github.com/backdrop-contrib/backdrop-drush-extension/archive/refs/heads/1.x-1.x.zip \
    && unzip 1.x-1.x.zip -d "/drush/drush${DRUSH_VERSION}/vendor/drush/drush/commands/backdrop" \
    && "/drush/drush${DRUSH_VERSION}/vendor/bin/drush" cc drush
