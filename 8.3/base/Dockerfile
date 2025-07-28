FROM php:8.3-apache

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

ENV PHP_MEMORY_LIMIT 4096M
ENV PHP_MAX_EXECUTION_TIME 600
ENV PHP_MAX_INPUT_TIME 600
ENV PHP_MAX_INPUT_VARS 3000
ENV PHP_UPLOAD_MAX_FILESIZE 64M
ENV PHP_POST_MAX_SIZE 64M
ENV PHP_CLEAR_ENV false

ENV SERVER_NAME default

ENV CODES_PORT 8080
ENV CODES_WORKING_DIR $APP_ROOT
ENV CODES_USER_DATA_DIR $APP_ROOT/.vscode
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
RUN apt-get install -y --no-install-recommends \
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
  libpcre3 \
  libpcre3-dev \
  libssl-dev \
  zlib1g-dev \
  zip unzip \
  git \
  rsync \
  ssh \
  default-mysql-client \
  && rm -rf /var/lib/apt/lists/*

# Install MailHog
# RUN wget https://github.com/mailhog/mhsendmail/releases/download/v0.2.0/mhsendmail_linux_amd64 \
#     && sudo chmod +x mhsendmail_linux_amd64 \
#     && sudo mv mhsendmail_linux_amd64 /usr/local/bin/mhsendmail

# Configure the gd library
RUN docker-php-ext-configure \
  gd --with-avif --with-freetype --with-jpeg --with-webp
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
  igbinary \
  oauth-2.0.7 \
  redis-5.3.7 \
  yaml-2.2.2 \
  memcached-3.2.0

RUN curl -L -o /tmp/imagick.tar.gz https://github.com/Imagick/imagick/archive/7088edc353f53c4bc644573a79cdcd67a726ae16.tar.gz \
    && tar --strip-components=1 -xf /tmp/imagick.tar.gz \
    && phpize \
    && ./configure \
    && make \
    && make install \
    && echo "extension=imagick.so" > /usr/local/etc/php/conf.d/ext-imagick.ini \
    && rm -rf /tmp/* \

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
  mysqli \
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

#== Enable mode_rewrite by default
RUN a2enmod rewrite remoteip headers

#== Install Codeserver
ARG CODESERVER_MAJOR_VERSION=4
RUN LATEST_VERSION=$(curl -s https://api.github.com/repos/coder/code-server/releases/latest | grep -oP '"tag_name": "v\K[^"]*') && \
  LATEST_MAJOR=$(echo $LATEST_VERSION | cut -d. -f1) && \
  if [ "$LATEST_MAJOR" = "$CODESERVER_MAJOR_VERSION" ]; then \
    CODESERVER_VERSION=$LATEST_VERSION; \
  else \
    CODESERVER_VERSION=$(curl -s https://api.github.com/repos/coder/code-server/releases | grep -oP '"tag_name": "v\K'$CODESERVER_MAJOR_VERSION'\.[^"]*' | head -1); \
  fi && \
  curl -fsSL https://code-server.dev/install.sh | sh -s -- --version=$CODESERVER_VERSION

#== Enable xdebug
RUN pecl install xdebug

#== Install Composer
RUN curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer --version=2.7.7
RUN curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer2 --version=2.7.7
RUN curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer1 --version=1.10.16

#== Install DevPanel CLI client
COPY bin/devpanel /usr/local/bin/devpanel
RUN chmod +x /usr/local/bin/devpanel \
  && devpanel version


#== Install Wordpress CLI
ARG WP_CLI_VERSION=2.9.0
RUN curl -LO https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar \
    && chmod +x wp-cli-${WP_CLI_VERSION}.phar \
    && mv wp-cli-${WP_CLI_VERSION}.phar /usr/local/bin/wp

WORKDIR ${APP_ROOT}


COPY drush /drush

USER ${USER}
RUN sudo chown -R ${USER} /drush

#== Install Drush
ARG DRUSH_VERSION=8
RUN composer update --working-dir=/drush/drush8 \
  && echo "alias drush8=/drush/drush8/vendor/bin/drush" >> ~/.bashrc
RUN  composer update --working-dir=/drush/drush9 \
  && echo "alias drush9=/drush/drush9/vendor/bin/drush" >> ~/.bashrc
RUN  composer update --working-dir=/drush/drush10 \
  && echo "alias drush10=/drush/drush10/vendor/bin/drush" >> ~/.bashrc
RUN  composer update --working-dir=/drush/drush11 \
  && echo "alias drush11=/drush/drush11/vendor/bin/drush" >> ~/.bashrc


#== Install Drush backdrop extention
RUN wget https://github.com/backdrop-contrib/backdrop-drush-extension/archive/refs/heads/1.x-1.x.zip \
  && unzip 1.x-1.x.zip -d /drush/drush${DRUSH_VERSION}/vendor/drush/drush/commands/backdrop \
  && /drush/drush${DRUSH_VERSION}/vendor/bin/drush cc drush


#== Install BEE CLI client
RUN sudo mkdir /bee && sudo git clone https://github.com/backdrop-contrib/bee.git /bee
RUN sudo chmod +x /bee/bee.php \
  && sudo ln -s /bee/bee.php /usr/bin/bee


RUN bash ~/.bashrc
RUN sudo ln -s /drush/drush${DRUSH_VERSION}/vendor/bin/drush /usr/bin/drush

#== Start apache.
COPY templates /templates
COPY scripts /scripts

#== Empty APP_ROOT to make container smaller
RUN sudo rm -rf ${APP_ROOT} && sudo sudo mkdir -p ${APP_ROOT}

CMD ["sudo", "-E", "/bin/bash", "/scripts/apache-start.sh" ]
