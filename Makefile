# =============================================================================
# Stratum — Makefile
# Unified interface for developers and AI agents.
# =============================================================================

.PHONY: up down reset logs console test test-core test-storage ps help

# Default target
help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  up            Start all services (uses existing .env + docker-compose.yml)"
	@echo "  down          Stop all services"
	@echo "  reset         Tear down, remove volumes, and start fresh"
	@echo "  logs          Tail logs for all services"
	@echo "  ps            Show container status"
	@echo "  console       Open Hasura console in browser"
	@echo ""
	@echo "  test          Run full integration tests (all scenarios)"
	@echo "  test-core     Run core-only scenario only"
	@echo "  test-storage  Run storage scenario only"

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
	URL="http://localhost:8080/console"; \
	echo "Opening Hasura Console: $$URL"; \
	open "$$URL" 2>/dev/null || xdg-open "$$URL" 2>/dev/null || echo "Visit: $$URL"

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test:
	@bash tests/integration/run.sh all

test-core:
	@bash tests/integration/run.sh core

test-storage:
	@bash tests/integration/run.sh storage
