FROM alpine:3.23

RUN apk add --no-cache \
	ca-certificates \
	curl \
	php84 \
	php84-fpm \
	php84-curl \
	php84-ctype \
	php84-dom \
	php84-exif \
	php84-fileinfo \
	php84-iconv \
	php84-mbstring \
	php84-mysqli \
	php84-opcache \
	php84-openssl \
	php84-phar \
	php84-session \
	php84-simplexml \
	php84-tokenizer \
	php84-xml \
	php84-zip

RUN printf '%s\n' 'memory_limit=256M' > /etc/php84/conf.d/99-wordpress.ini

RUN curl -fsSL \
	'https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar' \
	-o /usr/local/bin/wp \
	&& chmod 755 /usr/local/bin/wp \
	&& wp --info

RUN mkdir -p /usr/src/wordpress \
	&& wp core download --path=/usr/src/wordpress --allow-root

COPY conf/www.conf /etc/php84/php-fpm.d/www.conf
COPY tools/entrypoint.sh /usr/local/bin/wordpress-entrypoint.sh

RUN chmod 755 /usr/local/bin/wordpress-entrypoint.sh

WORKDIR /var/www/html

ENTRYPOINT ["/usr/local/bin/wordpress-entrypoint.sh"]
