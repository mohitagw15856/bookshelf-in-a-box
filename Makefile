# bookshelf-in-a-box — convenience commands
#
# Prefer plain English? Every target here just calls ./bin/bookshelf or a
# script in ./scripts. Run `make` or `make help` to see what's available.

SHELL := /bin/bash
BS := ./bin/bookshelf

.DEFAULT_GOAL := help

.PHONY: help setup up down restart status logs open wizard qr seed \
        backup restore update tailscale caddy backups check

help: ## Show this help
	@echo ""
	@echo "  📚 bookshelf-in-a-box"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
	@echo ""

setup: ## First-time setup (interactive)
	@./setup.sh

up: ## Start the library
	@$(BS) up

down: ## Stop the library (data is kept)
	@$(BS) down

restart: ## Restart the library
	@$(BS) restart

status: ## Show health, book count, disk, last backup
	@$(BS) status

logs: ## Follow the container logs
	@$(BS) logs

open: ## Open the library in your browser
	@$(BS) open

wizard: ## Open the first-run setup guide
	@$(BS) wizard

qr: ## Show a QR code to add the library on your phone
	@$(BS) qr

seed: ## Download a few free public-domain starter books
	@$(BS) seed

backup: ## Make a backup now
	@$(BS) backup

restore: ## Restore from a backup
	@$(BS) restore

update: ## Pull the latest image and recreate (data preserved)
	@$(BS) update

tailscale: ## Start the Tailscale add-on (read from anywhere)
	@$(BS) tailscale up

caddy: ## Start the HTTPS (Caddy) add-on
	@$(BS) caddy up

backups: ## Enable automatic nightly backups
	@$(BS) backups on

check: ## Validate compose files and lint scripts (needs shellcheck)
	@echo "==> docker compose config"; \
	cp -n .env.example .env 2>/dev/null || true; \
	docker compose config >/dev/null && echo "  base OK"; \
	docker compose -f docker-compose.yml -f docker-compose.caddy.yml config >/dev/null && echo "  + caddy OK"; \
	docker compose -f docker-compose.yml -f docker-compose.backup.yml config >/dev/null && echo "  + backup OK"; \
	TS_AUTHKEY=dummy docker compose -f docker-compose.yml -f docker-compose.tailscale.yml config >/dev/null && echo "  + tailscale OK"; \
	command -v shellcheck >/dev/null 2>&1 && { echo "==> shellcheck"; shellcheck -x -e SC1091 setup.sh bin/bookshelf scripts/*.sh && echo "  scripts OK"; } || echo "  (shellcheck not installed — skipping)"
