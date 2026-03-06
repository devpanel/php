# syntax=docker/dockerfile:1
# ─── PHP 7.4 base final image ─────────────────────────────────────────────────
# Extends the 'common-php-ext' intermediate (from base/Dockerfile) built with
# PHP_VERSION=7.4. Contains ONLY PHP 7.4 specific differences:
#   - libpcre3/libpcre3-dev (no libavif-dev)
#   - gd configure flags (no avif)
#   - PECL: igbinary 3.2.12, imagick via pecl, oauth extension
#   - WP-CLI 2.4.0 override (common installs 2.9.0)
#   - drush7 + drush11 symfony-5.4.18 override
#   - apache-start.sh override (extra WEB_ROOT substitution)
FROM common-php-ext AS final

# Switch to root for version-specific installation
USER root

# PHP 7.4 (Debian 10) specific packages: libpcre3/libpcre3-dev (no libavif-dev)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      libpcre3 \
      libpcre3-dev \
    && rm -rf /var/lib/apt/lists/*

# Configure gd (PHP 7.4: no avif support)
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp

RUN docker-php-ext-install -j$(nproc) gd

# PHP 7.4 PECL: igbinary 3.2.12, imagick via pecl, oauth extension
RUN pecl install -o -f \
      igbinary-3.2.12 \
      imagick-3.7.0 \
      oauth-2.0.7

RUN docker-php-ext-enable gd igbinary imagick oauth

# Override WP-CLI with 7.4-specific version (2.4.0)
RUN rm -f /usr/local/bin/wp \
    && curl -LO https://github.com/wp-cli/wp-cli/releases/download/v2.4.0/wp-cli-2.4.0.phar \
    && chmod +x wp-cli-2.4.0.phar \
    && mv wp-cli-2.4.0.phar /usr/local/bin/wp

# Overlay 7.4-specific drush files: drush7 (new) and drush11 symfony-5.4.18
# Docker COPY merges so common drush8/9/10 are preserved.
COPY drush /drush
RUN chown -R ${USER}:${GROUP} /drush

# Override apache-start.sh with 7.4-specific version
COPY scripts/apache-start.sh /scripts/apache-start.sh

USER ${USER}

# drush7 setup (7.4 only)
RUN composer update --working-dir=/drush/drush7 \
    && echo "alias drush7=/drush/drush7/vendor/bin/drush" >> ~/.bashrc

# Re-run drush11 composer update after symfony-5.4.18 override
# (alias already set by common stage; only the vendor dependencies change)
RUN composer update --working-dir=/drush/drush11
