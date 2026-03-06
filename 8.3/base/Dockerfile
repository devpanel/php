# syntax=docker/dockerfile:1
# ─── PHP 8.3 base final image ─────────────────────────────────────────────────
# Extends the 'common-php-ext' intermediate (from base/Dockerfile) built with
# PHP_VERSION=8.3. Contains ONLY PHP 8.3 specific differences:
#   - libavif-dev + libpcre2-dev
#   - gd configure flags (with avif)
#   - PECL: igbinary latest (no version pin), xdebug
#   - imagick built from source (pecl not compatible with 8.3)
#   - Composer 2.7.7 override (common installs 2.3.10)
#   - APP_ROOT cleanup (PHP 8.3 base image pre-populates /var/www/html)
FROM common-php-ext AS final

# Switch to root for version-specific installation
USER root

# PHP 8.3 specific packages: libavif-dev (avif gd support) and libpcre2-dev
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      libavif-dev \
      libpcre2-dev \
    && rm -rf /var/lib/apt/lists/*

# Configure gd with avif support (PHP 8.1+)
RUN docker-php-ext-configure gd --with-avif --with-freetype --with-jpeg --with-webp

RUN docker-php-ext-install -j$(nproc) gd

# PHP 8.3 PECL: igbinary latest (no version pin); xdebug added.
# imagick is NOT installed via pecl for 8.3 — built from source below.
RUN pecl install -o -f \
      igbinary \
      xdebug

# Build imagick from source (pecl package not compatible with PHP 8.3)
RUN curl -L -o /tmp/imagick.tar.gz \
      https://github.com/Imagick/imagick/archive/7088edc353f53c4bc644573a79cdcd67a726ae16.tar.gz \
    && tar --strip-components=1 -xf /tmp/imagick.tar.gz \
    && phpize \
    && ./configure \
    && make \
    && make install \
    && echo "extension=imagick.so" > /usr/local/etc/php/conf.d/ext-imagick.ini \
    && rm -rf /tmp/*

RUN docker-php-ext-enable gd igbinary xdebug

# Override Composer with PHP 8.3 version (2.7.7)
RUN rm -f /usr/local/bin/composer /usr/local/bin/composer2 \
    && curl -fsSL https://getcomposer.org/installer \
      | php -- --install-dir=/usr/local/bin --filename=composer  --version=2.7.7 \
    && ln -s /usr/local/bin/composer /usr/local/bin/composer2

# PHP 8.3: remove default Apache HTML content pre-populated by the base image
RUN rm -rf ${APP_ROOT} && mkdir -p ${APP_ROOT} \
    && chown -R ${USER}:${GROUP} ${APP_ROOT}

USER ${USER}
