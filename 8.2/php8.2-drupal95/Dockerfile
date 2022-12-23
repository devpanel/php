FROM php:8.2.1RC1-apache-buster

ARG POLYVER_CUSTOMER_KEY

#== System Environments
ENV USER www
ENV GROUP www
ENV UID 1000
ENV GID 1000
ENV SHELL /bin/bash

#== Default Environments
ENV APP_ROOT /var/www/html/
ENV WEB_ROOT $APP_ROOT
ENV PHP_CUSTOM_INI $APP_ROOT/php.ini
ENV PHP_EXT_DIR /usr/local/etc/php/conf.d

ENV PHP_CLEAR_ENV false
ENV PHP_MEMORY_LIMIT 2048M
ENV PHP_UPLOAD_MAX_FILESIZE 64M
ENV PHP_POST_MAX_SIZE 64M
ENV PHP_MAX_EXECUTION_TIME 600

ENV SERVER_NAME default

ENV CODES_PORT 8080
ENV CODES_WORKING_DIR $APP_ROOT
ENV CODES_ENABLE yes

ENV GIT_BRANCH master

ENV PHP_EXTENSIONS bcmath bz2 calendar exif gd gettext intl mysqli opcache pdo_mysql redis soap sockets sysvmsg sysvsem sysvshm xsl zip pcntl

# Install polimorphing if needed
RUN apt -y update && apt -y upgrade;
RUN if [ ! -z "$POLYVER_CUSTOMER_KEY" ]; then \
  curl -s https://repo.polyverse.io/cli | sh -s install cDDwaMuYf7BtSOt4jfJGl3TsA; \
  if [ $? -eq 0 ]; then \
  curl https://repo.polyverse.io/cli | bash -s replace-installed-elf; \
  fi; fi;

# Install dependencies
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
  apt-utils \
  sendmail-bin \
  sendmail \
  sudo \
  libbz2-dev \
  libjpeg62-turbo-dev \
  libpng-dev \
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
  zlib1g-dev \
  zip unzip \
  git \
  rsync \
  default-mysql-client \
  && rm -rf /var/lib/apt/lists/*

# Install MailHog
# RUN wget https://github.com/mailhog/mhsendmail/releases/download/v0.2.0/mhsendmail_linux_amd64 \
#     && sudo chmod +x mhsendmail_linux_amd64 \
#     && sudo mv mhsendmail_linux_amd64 /usr/local/bin/mhsendmail

# Configure the gd library
RUN docker-php-ext-configure \
  gd --with-freetype=/usr/include/ --with-jpeg=/usr/include/
# RUN docker-php-ext-configure \
#   ldap --with-libdir=lib/x86_64-linux-gnu
RUN docker-php-ext-configure \
  opcache --enable-opcache

# Install required PHP extensions
RUN docker-php-ext-install -j$(nproc) \
  bcmath \
  bz2 \
  calendar \
  exif \
  gd \
  gettext \
  gmp \
  intl \
#   ldap \
  mysqli \
  opcache \
  pdo_mysql \
  pspell \
  shmop \
  soap \
  sockets \
  sysvmsg \
  sysvsem \
  sysvshm \
  tidy \
  xsl \
  zip \
  pcntl

RUN pecl install -o -f \
  igbinary-3.2.12 \
  imagick-3.7.0 \
#   msgpack-2.1.1 \
  oauth-2.0.7 \
  redis-5.3.7 \
  yaml-2.2.2 \
  memcached-3.2.0

RUN rm -f /usr/local/etc/php/conf.d/*sodium.ini \
  && rm -f /usr/local/lib/php/extensions/*/*sodium.so \
  && apt-get remove libsodium* -y  \
  && mkdir -p /tmp/libsodium  \
  && curl -sL https://github.com/jedisct1/libsodium/archive/1.0.18-RELEASE.tar.gz | tar xzf - -C  /tmp/libsodium \
  && cd /tmp/libsodium/libsodium-1.0.18-RELEASE/ \
  && ./configure \
  && make && make check \
  && make install  \
  && cd / \
  && rm -rf /tmp/libsodium  \
  && pecl install -o -f libsodium

RUN docker-php-ext-enable \
  bcmath \
  bz2 \
  calendar \
  exif \
  gd \
  gettext \
  gmp \
  igbinary \
  imagick \
  intl \
#   ldap \
#   msgpack \
  mysqli \
  oauth \
  opcache \
  pdo_mysql \
  pspell \
  redis \
  shmop \
  soap \
  sockets \
  sodium \
  sysvmsg \
  sysvsem \
  sysvshm \
  tidy \
  xsl \
  yaml \
  zip \
  pcntl \
  memcached

RUN groupadd -g ${GID} ${GROUP} \
    && useradd --system --shell /bin/bash --uid ${UID} --gid ${GROUP}  --create-home --home-dir /home/${USER} ${USER} \
    && adduser ${USER} www-data \
    && apt install -y sudo \
    && usermod -aG sudo ${USER} \
    && echo "www    ALL=(ALL:ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN mkdir -p ${APP_ROOT} \
    && chown -R ${UID}:${GID} ${APP_ROOT}

#== Install Codeserver [AMD Chip]
# ARG CODESERVER_VERSION="4.9.1"
# COPY ./lib/code-server_${CODESERVER_VERSION}_amd64.deb /tmp/
# RUN dpkg -i /tmp/code-server_${CODESERVER_VERSION}_amd64.deb \
#     && rm /tmp/code-server_${CODESERVER_VERSION}_amd64.deb
#== Install Codeserver [ARM Chip]
ARG CODESERVER_VERSION="4.9.1"
COPY ./lib/code-server_${CODESERVER_VERSION}_arm64.deb /tmp/
RUN dpkg -i /tmp/code-server_${CODESERVER_VERSION}_arm64.deb \
    && rm /tmp/code-server_${CODESERVER_VERSION}_arm64.deb

#== Install Composer
RUN curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer --version=1.10.16

#== Install Wordpress CLI
ARG WP_CLI_VERSION=2.4.0
RUN curl -LO https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar \
    && chmod +x wp-cli-${WP_CLI_VERSION}.phar \
    && mv wp-cli-${WP_CLI_VERSION}.phar /usr/local/bin/wp

WORKDIR ${APP_ROOT}

COPY templates /templates
COPY scripts /scripts
COPY lib/drupal-9.5.0.zip /tmp

RUN unzip /tmp/drupal-9.5.0.zip 
RUN cp -r ${APP_ROOT}/drupal-9.5.0/* ${APP_ROOT}
RUN rm -rf /tmp/drupal-9.5.0.zip ${APP_ROOT}/drupal-9.5.0

USER ${USER}

#== Install Drush
ARG DRUSH_VERSION=8.x
RUN composer global require drush/drush:${DRUSH_VERSION} \
  && echo "PATH=/home/${USER}/.composer/vendor/bin/:${PATH}" >> ~/.bashrc
ENV PATH "/home/${USER}/.composer/vendor/bin/:${PATH}"

CMD ["sudo", "-E", "/bin/bash", "/scripts/apache-start.sh" ]