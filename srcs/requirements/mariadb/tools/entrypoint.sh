#!/bin/sh

set -eu

die()
{
	echo "mariadb-entrypoint: $*" >&2
	exit 1
}

: "${MYSQL_DATABASE:?MYSQL_DATABASE is required}"
: "${MYSQL_USER:?MYSQL_USER is required}"

case "$MYSQL_DATABASE" in
	*[!A-Za-z0-9_]*|'') die "MYSQL_DATABASE must contain only letters, digits, and underscores" ;;
esac

case "$MYSQL_USER" in
	*[!A-Za-z0-9_]*|'') die "MYSQL_USER must contain only letters, digits, and underscores" ;;
esac

DATA_DIR=/var/lib/mysql
INIT_SQL=/tmp/mariadb-init.sql
INIT_SOCKET=/run/mysqld/mariadb-init.sock

mkdir -p /run/mysqld
chown mysql:mysql /run/mysqld

if [ ! -d "$DATA_DIR/mysql" ]; then
	[ -r /run/secrets/db_password ] || die "missing /run/secrets/db_password"

	DB_PASSWORD=$(cat /run/secrets/db_password)
	[ -n "$DB_PASSWORD" ] || die "database password is empty"
	DB_PASSWORD_SQL=$(printf '%s' "$DB_PASSWORD" | sed -e 's/\\/\\\\/g' -e "s/'/''/g")

	cat > "$INIT_SQL" <<-SQL
	CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\`;
	CREATE USER IF NOT EXISTS '$MYSQL_USER'@'%' IDENTIFIED BY '$DB_PASSWORD_SQL';
	GRANT ALL PRIVILEGES ON \`$MYSQL_DATABASE\`.* TO '$MYSQL_USER'@'%';
	FLUSH PRIVILEGES;
	SQL

	mkdir -p "$DATA_DIR"
	chown -R mysql:mysql "$DATA_DIR"

	mariadb-install-db \
		--user=mysql \
		--datadir="$DATA_DIR" \
		--auth-root-authentication-method=socket \
		--skip-test-db

	/usr/bin/mariadbd \
		--user=mysql \
		--datadir="$DATA_DIR" \
		--skip-networking \
		--socket="$INIT_SOCKET" &
	INIT_PID=$!

	READY=0
	for i in $(seq 1 30); do
		if mariadb-admin --socket="$INIT_SOCKET" -u root ping >/dev/null 2>&1; then
			READY=1
			break
		fi
		sleep 1
	done
	[ "$READY" -eq 1 ] || die "temporary MariaDB server did not become ready"

	mariadb --socket="$INIT_SOCKET" -u root < "$INIT_SQL"
	mariadb-admin --socket="$INIT_SOCKET" -u root shutdown
	wait "$INIT_PID"

	rm -f "$INIT_SQL"
fi

exec /usr/bin/mariadbd --user=mysql
