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
	@echo "  test          Run all tests (smoke + install)"
	@echo "  test-smoke    Verify running stack is healthy"
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
	@bash tests/smoke/health-check.sh

test-install:
	@bash tests/scripts/test-install.sh
