FROM wordpress:php8.3-fpm

RUN apt-get update && apt-get install -y \
    libicu-dev \
    libzip-dev \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    mariadb-client \
    netcat-openbsd \
    unzip \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install intl zip gd opcache \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && rm -rf /var/lib/apt/lists/*

COPY php.ini /usr/local/etc/php/conf.d/custom.ini
COPY entrypoint.sh /usr/local/bin/wordpress-entrypoint-custom.sh

RUN chmod +x /usr/local/bin/wordpress-entrypoint-custom.sh

ENTRYPOINT ["wordpress-entrypoint-custom.sh"]
CMD ["php-fpm"]
