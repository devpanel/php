# syntax=docker/dockerfile:1
# ─── PHP 7.4 base final image ─────────────────────────────────────────────────
# 'common-php-ext' is the php-ext-common stage from base/Dockerfile, built
# with PHP_VERSION=7.4 by Docker Bake.  This Dockerfile adds only what differs
# for PHP 7.4: PCRE packages, gd configure flags, PECL extensions (igbinary
# pin, imagick via pecl, oauth), and tool versions (Composer 2.3.10,
# WP-CLI 2.4.0, drush7 + drush11 symfony-5.4.18 override).
FROM common-php-ext AS final

# PHP 7.4 (Debian 10) specific packages: libpcre3/libpcre3-dev (no libavif-dev)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      libpcre3 \
      libpcre3-dev \
    && rm -rf /var/lib/apt/lists/*

# Configure gd (PHP 7.4: no avif support, explicit include paths required)
RUN docker-php-ext-configure gd \
      --with-freetype=/usr/include/ \
      --with-jpeg=/usr/include/ \
      --with-webp=/usr/include/

RUN docker-php-ext-install -j$(nproc) gd

# PHP 7.4 PECL: igbinary 3.2.12, imagick via pecl, oauth extension
RUN pecl install -o -f \
      igbinary-3.2.12 \
      imagick-3.7.0 \
      oauth-2.0.7

RUN docker-php-ext-enable gd igbinary imagick oauth

# Install code-server (pre-downloaded in downloader stage)
COPY --from=common-downloader /tmp/code-server.deb /tmp/code-server.deb
RUN dpkg -i /tmp/code-server.deb \
    || { apt-get update && apt-get install -y -f --no-install-recommends \
         && rm -rf /var/lib/apt/lists/*; dpkg -i /tmp/code-server.deb; } \
    && rm /tmp/code-server.deb

# Install Composer (PHP 7.4 uses 2.3.10)
RUN curl -fsSL https://getcomposer.org/installer \
      | php -- --install-dir=/usr/local/bin --filename=composer  --version=2.3.10 \
    && curl -fsSL https://getcomposer.org/installer \
      | php -- --install-dir=/usr/local/bin --filename=composer2 --version=2.3.10 \
    && curl -fsSL https://getcomposer.org/installer \
      | php -- --install-dir=/usr/local/bin --filename=composer1 --version=1.10.16

# Install WP-CLI (PHP 7.4 uses 2.4.0)
RUN curl -LO https://github.com/wp-cli/wp-cli/releases/download/v2.4.0/wp-cli-2.4.0.phar \
    && chmod +x wp-cli-2.4.0.phar \
    && mv wp-cli-2.4.0.phar /usr/local/bin/wp

# Install BEE CLI
RUN mkdir /bee && git clone https://github.com/backdrop-contrib/bee.git /bee \
    && chmod +x /bee/bee.php \
    && ln -s /bee/bee.php /usr/bin/bee

# Overlay 7.4-specific drush files: drush7 (new) and drush11 with symfony 5.4.18
# (overrides the common drush11 from base/Dockerfile's php-ext-common stage).
# Docker COPY merges into /drush so the common drush8/9/10 directories are kept.
COPY drush /drush

# Override apache-start.sh with 7.4-specific version (has extra WEB_ROOT substitution)
COPY scripts/apache-start.sh /scripts/apache-start.sh

ARG DRUSH_VERSION=8
RUN ln -s /drush/drush${DRUSH_VERSION}/vendor/bin/drush /usr/bin/drush \
    && mkdir -p /home/${USER}/.config/code-server \
    && chown -R ${USER}:${GROUP} /drush /bee /home/${USER} ${APP_ROOT}

USER ${USER}
WORKDIR ${APP_ROOT}

RUN touch /home/${USER}/.config/code-server/config.yaml

RUN composer update --working-dir=/drush/drush7 \
    && echo "alias drush7=/drush/drush7/vendor/bin/drush" >> ~/.bashrc
RUN composer update --working-dir=/drush/drush8 \
    && echo "alias drush8=/drush/drush8/vendor/bin/drush" >> ~/.bashrc
RUN composer update --working-dir=/drush/drush9 \
    && echo "alias drush9=/drush/drush9/vendor/bin/drush" >> ~/.bashrc
RUN composer update --working-dir=/drush/drush10 \
    && echo "alias drush10=/drush/drush10/vendor/bin/drush" >> ~/.bashrc
RUN composer update --working-dir=/drush/drush11 \
    && echo "alias drush11=/drush/drush11/vendor/bin/drush" >> ~/.bashrc

RUN wget https://github.com/backdrop-contrib/backdrop-drush-extension/archive/refs/heads/1.x-1.x.zip \
    && unzip 1.x-1.x.zip -d /drush/drush${DRUSH_VERSION}/vendor/drush/drush/commands/backdrop \
    && /drush/drush${DRUSH_VERSION}/vendor/bin/drush cc drush

CMD ["sudo", "-E", "/bin/bash", "/scripts/apache-start.sh"]
