# User documentation

## 1. What the stack provides

```text
Browser :443 -> NGINX :443 -> WordPress/PHP-FPM :9000 -> MariaDB :3306
                         \
                          -> wordpress_data / mariadb_data
```

NGINX provides HTTPS, WordPress provides the website, and MariaDB stores the
WordPress data. Only NGINX is reachable from the host.

## 2. Start and stop

Run `make` to build and start the stack. Run `make down` to stop and remove
the containers and network while keeping persistent data. Run `make clean` to
also remove locally built images. Run `make fclean CONFIRM=yes` to remove
containers, images, Docker volumes, and the data under `DATA_PATH`; this is a
destructive cleanup.

## 3. Site and administration

Add the following entry to the host `/etc/hosts` file:

```text
127.0.0.1 tasugiya.42.fr
```

Open [https://tasugiya.42.fr/](https://tasugiya.42.fr/) for the site and
`https://tasugiya.42.fr/wp-admin/` for administration. The local certificate
is self-signed, so the browser may show a certificate warning.

## 4. Configuration and credentials

Non-secret values are in `srcs/.env`. Passwords are in these local files:

- `secrets/db_password.txt`
- `secrets/wp_admin_password.txt`
- `secrets/wp_user_password.txt`

These files must be created from their `.example` files and must not be
committed. After changing non-secret settings, run `make re`. Changing a
password for an existing installation also requires updating the corresponding
database or WordPress account; a clean rebuild removes the existing data.

## 5. Normal operation check

Run:

```sh
make ps
make logs
```

Normally `mariadb` is `Up` and `healthy`, while `wordpress` and `nginx` are
`Up`. The host-published port is `443` on NGINX only. MariaDB's Compose
healthcheck must be healthy before WordPress starts.
