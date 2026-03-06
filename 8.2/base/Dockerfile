# syntax=docker/dockerfile:1
# ─── PHP 8.2 base final image ─────────────────────────────────────────────────
# 'common-php-ext' is the php-ext-common stage from base/Dockerfile, built
# with PHP_VERSION=8.2 by Docker Bake.  This Dockerfile adds only what differs
# for PHP 8.2: avif + PCRE packages, gd configure flags (with avif), PECL
# extensions (igbinary 3.2.12, imagick via pecl), and common tool versions.
FROM common-php-ext AS final

# PHP 8.2+ specific packages: libavif-dev (avif gd support) and libpcre2-dev
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      libavif-dev \
      libpcre2-dev \
    && rm -rf /var/lib/apt/lists/*

# Configure gd with avif support (PHP 8.1+)
RUN docker-php-ext-configure gd --with-avif --with-freetype --with-jpeg --with-webp

RUN docker-php-ext-install -j$(nproc) gd

# PHP 8.2 PECL: igbinary 3.2.12, imagick via pecl (no oauth, no xdebug)
RUN pecl install -o -f \
      igbinary-3.2.12 \
      imagick-3.7.0

RUN docker-php-ext-enable gd igbinary imagick

# Install code-server (pre-downloaded in downloader stage)
COPY --from=common-downloader /tmp/code-server.deb /tmp/code-server.deb
RUN dpkg -i /tmp/code-server.deb \
    || { apt-get update && apt-get install -y -f --no-install-recommends \
         && rm -rf /var/lib/apt/lists/*; dpkg -i /tmp/code-server.deb; } \
    && rm /tmp/code-server.deb

# Install Composer (PHP 8.2 uses 2.3.10)
RUN curl -fsSL https://getcomposer.org/installer \
      | php -- --install-dir=/usr/local/bin --filename=composer  --version=2.3.10 \
    && curl -fsSL https://getcomposer.org/installer \
      | php -- --install-dir=/usr/local/bin --filename=composer2 --version=2.3.10 \
    && curl -fsSL https://getcomposer.org/installer \
      | php -- --install-dir=/usr/local/bin --filename=composer1 --version=1.10.16

# Install WP-CLI
RUN curl -LO https://github.com/wp-cli/wp-cli/releases/download/v2.9.0/wp-cli-2.9.0.phar \
    && chmod +x wp-cli-2.9.0.phar \
    && mv wp-cli-2.9.0.phar /usr/local/bin/wp

# Install BEE CLI
RUN mkdir /bee && git clone https://github.com/backdrop-contrib/bee.git /bee \
    && chmod +x /bee/bee.php \
    && ln -s /bee/bee.php /usr/bin/bee

ARG DRUSH_VERSION=8
RUN ln -s /drush/drush${DRUSH_VERSION}/vendor/bin/drush /usr/bin/drush \
    && mkdir -p /home/${USER}/.config/code-server \
    && chown -R ${USER}:${GROUP} /drush /bee /home/${USER} ${APP_ROOT}

USER ${USER}
WORKDIR ${APP_ROOT}

RUN touch /home/${USER}/.config/code-server/config.yaml

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
