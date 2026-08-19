#!/bin/sh

set -eu

die()
{
	echo "wordpress-entrypoint: $*" >&2
	exit 1
}

: "${DOMAIN_NAME:?DOMAIN_NAME is required}"
: "${MYSQL_DATABASE:?MYSQL_DATABASE is required}"
: "${MYSQL_USER:?MYSQL_USER is required}"
: "${WP_TITLE:?WP_TITLE is required}"
: "${WP_ADMIN_USER:?WP_ADMIN_USER is required}"
: "${WP_ADMIN_EMAIL:?WP_ADMIN_EMAIL is required}"
: "${WP_USER:?WP_USER is required}"
: "${WP_USER_EMAIL:?WP_USER_EMAIL is required}"

ADMIN_USER_LOWER=$(printf '%s' "$WP_ADMIN_USER" | tr '[:upper:]' '[:lower:]')
case "$ADMIN_USER_LOWER" in
	*admin*) die "WP_ADMIN_USER must not contain admin" ;;
esac

read_secret()
{
	SECRET_FILE=$1
	[ -r "$SECRET_FILE" ] || die "missing $SECRET_FILE"
	SECRET_VALUE=$(cat "$SECRET_FILE")
	[ -n "$SECRET_VALUE" ] || die "$SECRET_FILE is empty"
	printf '%s' "$SECRET_VALUE"
}

DB_PASSWORD=$(read_secret /run/secrets/db_password)
WP_ADMIN_PASSWORD=$(read_secret /run/secrets/wp_admin_password)
WP_USER_PASSWORD=$(read_secret /run/secrets/wp_user_password)

if [ -z "$(find /var/www/html -mindepth 1 -maxdepth 1 -print -quit)" ]; then
	cp -a /usr/src/wordpress/. /var/www/html/
fi

if ! wp core is-installed --path=/var/www/html --allow-root >/dev/null 2>&1; then
	wp config create \
		--path=/var/www/html \
		--dbname="$MYSQL_DATABASE" \
		--dbuser="$MYSQL_USER" \
		--dbpass="$DB_PASSWORD" \
		--dbhost=mariadb:3306 \
		--allow-root

	wp core install \
		--path=/var/www/html \
		--url="https://$DOMAIN_NAME" \
		--title="$WP_TITLE" \
		--admin_user="$WP_ADMIN_USER" \
		--admin_password="$WP_ADMIN_PASSWORD" \
		--admin_email="$WP_ADMIN_EMAIL" \
		--skip-email \
		--allow-root

	wp user create "$WP_USER" "$WP_USER_EMAIL" \
		--role=author \
		--user_pass="$WP_USER_PASSWORD" \
		--path=/var/www/html \
		--allow-root
fi

chown -R nobody:nobody /var/www/html

exec /usr/sbin/php-fpm84 -F
