# Developer documentation

## 1. Prerequisites

Use either a Debian VM or the WSL2 development environment with Docker
Engine and Docker Compose v2. The user must be able to run Docker commands.
For local access, add `127.0.0.1 tasugiya.42.fr` to `/etc/hosts`. The WSL2
environment is used during development; the Debian VM is the target for the
school-machine rehearsal.

## 2. Clean setup

From a clean clone:

```sh
git clone <repository-url>
cd git-inception
cp srcs/.env.example srcs/.env
cp secrets/db_password.txt.example secrets/db_password.txt
cp secrets/wp_admin_password.txt.example secrets/wp_admin_password.txt
cp secrets/wp_user_password.txt.example secrets/wp_user_password.txt
```

Set `DOMAIN_NAME`, `DATA_PATH`, and the other non-secret values in
`srcs/.env`. Replace `CHANGE_ME` in all three secret files, then run:

```sh
make check
make
```

## 3. Makefile and Compose relation

The Makefile invokes Compose with the project configuration:

```text
docker compose --env-file srcs/.env -f srcs/docker-compose.yml
```

| Target | Action |
| --- | --- |
| `make` / `make up` | Validate configuration, create data directories, build, and start services. |
| `make check` | Validate `.env` and the three secret files. |
| `make dirs` | Create the two host data directories. |
| `make down` | Stop and remove containers and the network. |
| `make re` | Run `down`, then `up`. |
| `make clean` | Stop the stack and remove locally built images. |
| `make fclean CONFIRM=yes` | Remove all Compose resources and data under `DATA_PATH`. |
| `make logs` / `make ps` | Follow logs or display service status. |

Compose defines the three services, the private bridge network, named
volumes, Docker secrets, MariaDB healthcheck, and startup dependencies.

## 4. Container and volume inspection

Useful commands are:

```sh
make ps
make logs
docker compose --env-file srcs/.env -f srcs/docker-compose.yml config --quiet
docker exec nginx ps
docker exec wordpress ps
docker exec mariadb ps
docker volume ls
docker volume inspect <project>_mariadb_data
docker volume inspect <project>_wordpress_data
```

The exact Compose project prefix may change the volume names.

## 5. Data paths and persistence

`mariadb_data` is mounted at `/var/lib/mysql` and uses
`/home/tasugiya/data/mariadb` as its host device. `wordpress_data` is mounted
at `/var/www/html` and uses `/home/tasugiya/data/wordpress`.

For example, `docker volume inspect` should show a device similar to:

```json
"Device": "/home/tasugiya/data/mariadb"
```

`make down` keeps these data paths. `make fclean CONFIRM=yes` removes their
contents after removing the Compose volumes.

## 6. Troubleshooting

- **502 Bad Gateway:** run `make ps` and `make logs`; check that WordPress is
  running and PHP-FPM is listening on the internal port 9000.
- **Database failure or WordPress cannot connect:** confirm that MariaDB is
  `healthy`, the database secret and `.env` values match, and inspect
  `docker compose ... logs mariadb`.
- **Port 443 is already in use:** identify the process with `sudo ss -ltnp
  | grep ':443'`, then stop it or choose an unused development setup.
- **Certificate or domain failure:** verify `/etc/hosts`, `DOMAIN_NAME`, and
  the NGINX certificate configuration, then run `make re`.
