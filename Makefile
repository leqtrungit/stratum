# =============================================================================
# Stratum — Makefile
# Unified interface for developers and AI agents.
# =============================================================================

.PHONY: up down reset logs console test test-smoke test-install ps help

# Default target
help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  up            Start all services"
	@echo "  down          Stop all services"
	@echo "  reset         Tear down, remove volumes, and start fresh"
	@echo "  logs          Tail logs for all services"
	@echo "  ps            Show container status"
	@echo "  console       Open Hasura console in browser"
	@echo ""
	@echo "  test          Run all tests (install + rebuild stack + smoke)"
	@echo "  test-smoke    Rebuild stack with latest code, then verify health"
	@echo "  test-install  Verify install/bootstrap scripts produce correct output"

# ---------------------------------------------------------------------------
# Stack lifecycle
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
	ADMIN_SECRET=$${HASURA_GRAPHQL_ADMIN_SECRET:-}; \
	URL="http://localhost:8080/console"; \
	echo "Opening Hasura Console: $$URL"; \
	open "$$URL" 2>/dev/null || xdg-open "$$URL" 2>/dev/null || echo "Visit: $$URL"

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test: test-install test-smoke

test-smoke:
	@echo "Rebuilding and restarting stack..."
	@docker compose up --build -d
	@bash tests/smoke/health-check.sh

test-install:
	@bash tests/scripts/test-install.sh
