# syntax=docker/dockerfile:1@sha256:572cebbc2b15e6f84c077742952674889cb63cd5e9b80abdffcbe587b6f19183
# ─── PHP 7.4 base final image ─────────────────────────────────────────────────
# Extends the 'common-php-ext' intermediate (from base/Dockerfile) built with
# PHP_VERSION=7.4. Contains ONLY PHP 7.4 specific differences:
#   - libpcre3/libpcre3-dev (no libavif-dev) + gd build libs: installed, used, removed
#   - libmagickwand-dev + libmagickcore-dev for imagick: installed, used, removed
#   - libpspell-dev for pspell: installed, used, removed
#   - gd configure flags (no avif)
#   - PECL: igbinary 3.2.16, imagick 3.8.1, oauth extension
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
# renovate: datasource=github-tags depName=igbinary/igbinary extractVersion=^(?<version>\d+\.\d+\.\d+)$
ARG PECL_IGBINARY_VERSION=3.2.16
# renovate: datasource=github-tags depName=Imagick/imagick extractVersion=^(?<version>\d+\.\d+\.\d+)$
ARG PECL_IMAGICK_VERSION=3.8.1
# renovate: datasource=github-tags depName=php/pecl-web_services-oauth extractVersion=^(?<version>\d+\.\d+\.\d+)$
ARG PECL_OAUTH_VERSION=2.0.7
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
        "igbinary-${PECL_IGBINARY_VERSION}" \
        "imagick-${PECL_IMAGICK_VERSION}" \
        "oauth-${PECL_OAUTH_VERSION}" \
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
            | xargs -r apt-mark manual; } \
    && apt-get purge -y --auto-remove \
        -o APT::AutoRemove::RecommendsImportant=false \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/apt/apt.conf.d/01dpkg-no-pty

# Install psql 18x
RUN echo 'Dpkg::Use-Pty "0";' > /etc/apt/apt.conf.d/01dpkg-no-pty \
    && for i in $(seq 1 3); do \
      apt-get update && apt-get upgrade -y --fix-missing \
        && apt-get install -f -y --no-install-recommends \
        && apt-get install -y --fix-missing --no-install-recommends \
          gnupg \
          lsb-release \
        && break; \
      [ "$i" -lt 3 ] && sleep 5; \
    done \
    && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] https://apt-archive.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg-archive main" \
       > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get install -y postgresql-client-18 \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/apt/apt.conf.d/01dpkg-no-pty

# Override WP-CLI with 7.4-specific version (2.4.0)
# renovate: datasource=github-releases depName=wp-cli/wp-cli extractVersion=^v(?<version>.+)$
ARG WP_CLI_VERSION=2.4.0
RUN rm -f /usr/local/bin/wp \
    && curl -fsSLO "https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar" \
    && chmod +x "wp-cli-${WP_CLI_VERSION}.phar" \
    && mv "wp-cli-${WP_CLI_VERSION}.phar" /usr/local/bin/wp

# Overlay 7.4-specific drush files: drush7 (PHP 7.4 only).
# Docker COPY merges so common drush8/9/10/11 are preserved.
COPY drush /drush
RUN chown -R ${USER}:${GROUP} /drush

USER ${USER}

# drush7 setup (7.4 only)
RUN composer update --working-dir=/drush/drush7 \
    && echo "alias drush7=/drush/drush7/vendor/bin/drush" >> ~/.bashrc
