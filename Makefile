# =============================================================================
# Stratum — Makefile
# Unified interface for developers and AI agents.
# =============================================================================

.PHONY: up down reset logs console ps help \
        dev dev-down dev-logs dev-reset hasura-console

DEV_COMPOSE = docker compose -f docker-compose.yml -f docker-compose.dev.yml

# Default target
help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  up            Start all services (production mode)"
	@echo "  down          Stop all services"
	@echo "  reset         Tear down, remove volumes, and start fresh"
	@echo "  logs          Tail logs for all services"
	@echo "  ps            Show container status"
	@echo ""
	@echo "  dev           Start stack in dev mode (hot reload, ports exposed)"
	@echo "  dev-down      Stop dev stack"
	@echo "  dev-logs      Tail dev stack logs"
	@echo "  dev-reset     Full dev reset (removes volumes)"
	@echo "  hasura-console  Open Hasura CLI console (tracks schema changes to files)"
	@echo ""
	@echo "  test          Run full integration tests (all scenarios)"
	@echo "  test-core     Run core-only scenario only"
	@echo "  test-storage  Run storage scenario only"

# ---------------------------------------------------------------------------
# Production stack
# ---------------------------------------------------------------------------

up:
	docker compose up -d

down:
	docker compose down

reset:
	docker compose down -v --remove-orphans
	docker compose up -d

logs:
	docker compose logs -f

ps:
	docker compose ps

console:
	@source .env 2>/dev/null; \
	URL="http://localhost:8080/console"; \
	echo "Opening Hasura Console: $$URL"; \
	open "$$URL" 2>/dev/null || xdg-open "$$URL" 2>/dev/null || echo "Visit: $$URL"

# ---------------------------------------------------------------------------
# Dev stack (hot reload + exposed ports)
# ---------------------------------------------------------------------------

dev:
	$(DEV_COMPOSE) up -d

dev-down:
	$(DEV_COMPOSE) down

dev-logs:
	$(DEV_COMPOSE) logs -f

dev-reset:
	$(DEV_COMPOSE) down -v --remove-orphans
	$(DEV_COMPOSE) up -d

hasura-console:
	@HASURA_GRAPHQL_ADMIN_SECRET=$$(grep '^HASURA_GRAPHQL_ADMIN_SECRET=' .env | cut -d= -f2) \
	hasura console --project hasura

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test:
	@bash tests/integration/run.sh all

test-core:
	@bash tests/integration/run.sh core

test-storage:
	@bash tests/integration/run.sh storage
