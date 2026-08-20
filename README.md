*This project has been created as part of the 42 curriculum by tasugiya.*

## Description

This project builds a WordPress website with Docker Compose. It contains three
custom containers:

- NGINX: HTTPS entry point on port 443 and FastCGI proxy.
- WordPress: PHP-FPM and WordPress application.
- MariaDB: the WordPress database.

Only NGINX is exposed to the host. The containers communicate through the
private `inception` Docker network.

## Instructions

### Prerequisites

- Docker Engine with Docker Compose v2.
- A host entry for local access:

  ```text
  127.0.0.1 tasugiya.42.fr
  ```

### Setup

From the repository root, create the local configuration files:

```sh
cp srcs/.env.example srcs/.env
cp secrets/db_password.txt.example secrets/db_password.txt
cp secrets/wp_admin_password.txt.example secrets/wp_admin_password.txt
cp secrets/wp_user_password.txt.example secrets/wp_user_password.txt
```

Replace every `CHANGE_ME` value. Keep passwords in `secrets/` and non-secret
settings in `srcs/.env`.

### Start, stop, and access

```sh
make
```

Open `https://tasugiya.42.fr/`. The certificate is self-signed, so a browser
warning is expected in this local project.

Useful targets are `make ps`, `make logs`, `make down`, and
`make fclean CONFIRM=yes`. `fclean` removes containers, images, volumes, and
data under `DATA_PATH`.

## Project description

### Docker usage and included source

The Compose file defines the MariaDB, WordPress, and NGINX services, their
network, health check, dependencies, secrets, and volumes. Each service has a
Dockerfile and service configuration under `srcs/requirements/`.

### Main design decisions

- Each container runs its service in the foreground as PID 1; no keep-alive
  loop is used.
- Passwords are supplied as Docker secrets. Non-secret configuration is read
  from `srcs/.env`.
- Named volumes use the local driver with `driver_opts` and persist data under
  `/home/tasugiya/data/mariadb` and `/home/tasugiya/data/wordpress`.
- The containers use a user-defined bridge network, and only NGINX publishes
  port 443.

### Comparisons

| Topic | Choice in this project | Comparison |
| --- | --- | --- |
| VM vs Docker | Docker containers | Containers are lighter and isolate one service per container; a VM virtualizes a complete guest system. |
| Secrets vs environment variables | Passwords use Docker secrets; other settings use `.env` | Secrets avoid placing password values in the Compose environment; `.env` is suitable for non-secret configuration. |
| Docker network vs host network | User-defined bridge network | Service names provide internal communication without exposing MariaDB or WordPress ports; host networking would share the host network namespace. |
| Docker Volumes vs Bind Mounts | Named volumes with the local driver | A Docker volume is referenced and managed by Docker, while a bind mount maps a specific host path directly. This project uses the named volumes `mariadb_data` and `wordpress_data`, configured with `driver_opts` so their data is stored in the required host paths. |

## Resources

- [Dockerfile reference](https://docs.docker.com/reference/dockerfile/)
- [Compose services](https://docs.docker.com/reference/compose-file/services/)
- [Compose volumes](https://docs.docker.com/reference/compose-file/volumes/)
- [Compose secrets](https://docs.docker.com/reference/compose-file/secrets/)
- [Compose startup order](https://docs.docker.com/compose/how-tos/startup-order/)
- [NGINX HTTPS configuration](https://nginx.org/en/docs/http/configuring_https_servers.html)
- [WordPress installation requirements](https://developer.wordpress.org/advanced-administration/before-install/)

AI was used to help organize this documentation, cross-check official
documentation, and review implementation and test results. The final
configuration and commands were reviewed in the project environment.
