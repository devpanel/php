# syntax=docker/dockerfile:1
# ─── Stage 0: Pre-downloaded artifacts ────────────────────────────────────────
FROM common-downloader AS downloader

# ─── Stage 1: PHP 8.1 runtime with extensions ─────────────────────────────────
FROM php:8.2-apache AS php-ext

#== System Environments
ENV USER=www
ENV GROUP=www
ENV UID=1000
ENV GID=1000
ENV HOME=/home/www
ENV SHELL=/bin/bash

#== Default Environments
ENV APP_ROOT=/var/www/html
ENV WEB_ROOT=$APP_ROOT
ENV PHP_CUSTOM_INI=$APP_ROOT/php.ini
ENV PHP_EXT_DIR=/usr/local/etc/php/conf.d

ENV PHP_MEMORY_LIMIT=4096M
ENV PHP_MAX_EXECUTION_TIME=600
ENV PHP_MAX_INPUT_TIME=600
ENV PHP_MAX_INPUT_VARS=3000
ENV PHP_UPLOAD_MAX_FILESIZE=64M
ENV PHP_POST_MAX_SIZE=64M
ENV PHP_CLEAR_ENV=false

ENV SERVER_NAME=default
ENV GIT_BRANCH=master

ENV CODES_PORT=8080
ENV CODES_WORKING_DIR=$APP_ROOT
ENV CODES_USER_DATA_DIR=$APP_ROOT/.vscode
ENV CODES_ENABLE=yes

# Install dependencies.
# PHP 8.2+: libavif-dev (avif gd support) and libpcre2-dev.
RUN apt-get update && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
      apt-utils \
      sendmail-bin \
      sendmail \
      sudo \
      libavif-dev \
      libbz2-dev \
      libjpeg62-turbo-dev \
      libpng-dev \
      libwebp-dev \
      libfreetype6-dev \
      libgeoip-dev \
      wget \
      libgmp-dev \
      libmagickwand-dev \
      libmagickcore-dev \
      libicu-dev \
      libldap2-dev \
      libpspell-dev \
      libtidy-dev \
      libxslt1-dev \
      libyaml-dev \
      libzip-dev \
      libmemcached-dev \
      libpcre2-dev \
      libssl-dev \
      zlib1g-dev \
      zip unzip \
      git \
      rsync \
      ssh \
      default-mysql-client \
    && rm -rf /var/lib/apt/lists/*

# Configure gd (PHP 8.1+: avif support, shorter flag syntax)
RUN docker-php-ext-configure gd --with-avif --with-freetype --with-jpeg --with-webp
RUN docker-php-ext-configure opcache --enable-opcache

# Install required PHP extensions
RUN docker-php-ext-install -j$(nproc) \
      bcmath bz2 calendar exif gd gettext gmp intl mysqli opcache \
      pdo_mysql pspell shmop soap sockets sysvmsg sysvsem sysvshm \
      tidy xsl zip pcntl

# Install PECL extensions.
# PHP 8.2: igbinary pinned to 3.2.12; imagick via pecl.
RUN pecl install -o -f \
      igbinary-3.2.12 \
      imagick-3.7.0 \
      redis-5.3.7 \
      yaml-2.2.2 \
      memcached-3.2.0

# Install libsodium (source pre-downloaded in the 'downloader' stage)
COPY --from=downloader /tmp/libsodium /tmp/libsodium
RUN rm -f /usr/local/etc/php/conf.d/*sodium.ini \
    && rm -f /usr/local/lib/php/extensions/*/*sodium.so \
    && apt-get remove libsodium* -y \
    && cd /tmp/libsodium/libsodium-1.0.18-RELEASE/ \
    && ./configure && make && make check && make install \
    && cd / && rm -rf /tmp/libsodium \
    && pecl install -o -f libsodium

# Enable PHP extensions
RUN docker-php-ext-enable \
      bcmath bz2 calendar exif gd gettext gmp igbinary imagick intl mysqli \
      opcache pdo_mysql pspell redis shmop soap sockets sodium sysvmsg \
      sysvsem sysvshm tidy xsl yaml zip pcntl memcached

RUN groupadd -g ${GID} ${GROUP} \
    && useradd --system --shell /bin/bash --uid ${UID} --gid ${GROUP} \
               --create-home --home-dir /home/${USER} ${USER} \
    && adduser ${USER} www-data \
    && apt-get install -y sudo \
    && usermod -aG sudo ${USER} \
    && echo "www    ALL=(ALL:ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN mkdir -p ${APP_ROOT} && chown -R ${UID}:${GID} ${APP_ROOT}

RUN a2enmod rewrite remoteip headers

# Copy common assets from the 'common' build context (./base/ directory)
COPY --from=common bin/devpanel /usr/local/bin/devpanel
RUN chmod +x /usr/local/bin/devpanel && devpanel version
COPY --from=common templates /templates
COPY --from=common scripts   /scripts
COPY --from=common drush     /drush

# ─── Stage 2: PHP 8.1 final image with application-level tools ────────────────
FROM php-ext AS final

# Install code-server (pre-downloaded in 'downloader' stage)
COPY --from=downloader /tmp/code-server.deb /tmp/code-server.deb
RUN dpkg -i /tmp/code-server.deb \
    || { apt-get update && apt-get install -y -f --no-install-recommends \
         && rm -rf /var/lib/apt/lists/*; dpkg -i /tmp/code-server.deb; } \
    && rm /tmp/code-server.deb

# Install Composer (PHP 8.1 uses 2.3.10)
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

WORKDIR ${APP_ROOT}
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
