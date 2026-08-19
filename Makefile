ENV_FILE := srcs/.env
COMPOSE_FILE := srcs/docker-compose.yml
COMPOSE := docker compose --env-file $(ENV_FILE) -f $(COMPOSE_FILE)
DATA_PATH := $(shell sed -n 's/^DATA_PATH=//p' $(ENV_FILE) 2>/dev/null)

.DEFAULT_GOAL := all

.PHONY: all check dirs up down re clean fclean logs ps

all: up

check:
	@set -eu; \
	if [ ! -f "$(ENV_FILE)" ]; then \
		echo "Missing $(ENV_FILE). Copy srcs/.env.example and set the values." >&2; \
		exit 1; \
	fi; \
	if grep -q 'CHANGE_ME' "$(ENV_FILE)"; then \
		echo "Replace CHANGE_ME in $(ENV_FILE) before starting the project." >&2; \
		exit 1; \
	fi; \
	if ! grep -Eq '^DATA_PATH=/[^[:space:]]*$$' "$(ENV_FILE)"; then \
		echo "DATA_PATH is missing or invalid in $(ENV_FILE)." >&2; \
		exit 1; \
	fi; \
	for secret in secrets/db_password.txt secrets/wp_admin_password.txt secrets/wp_user_password.txt; do \
		if [ ! -s "$$secret" ]; then \
			echo "Missing or empty $$secret. Copy the matching .example file and set a password." >&2; \
			exit 1; \
		fi; \
		if grep -q 'CHANGE_ME' "$$secret"; then \
			echo "Replace CHANGE_ME in $$secret before starting the project." >&2; \
			exit 1; \
		fi; \
	done

dirs: check
	@test -n "$(DATA_PATH)" || { echo "DATA_PATH is empty." >&2; exit 1; }
	@mkdir -p "$(DATA_PATH)/mariadb" "$(DATA_PATH)/wordpress"

up: check dirs
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

re: down up

clean:
	$(COMPOSE) down --rmi local

fclean: check
	@if [ "$(CONFIRM)" != "yes" ]; then \
		echo "This removes containers, images, volumes, and data under $(DATA_PATH)." >&2; \
		echo "If this is intentional, run: make fclean CONFIRM=yes" >&2; \
		exit 1; \
	fi
	$(COMPOSE) down --rmi all --volumes --remove-orphans
	@if [ -n "$(DATA_PATH)" ] && [ -d "$(DATA_PATH)" ]; then \
		sudo find "$(DATA_PATH)" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +; \
	fi

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps
