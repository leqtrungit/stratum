#!/usr/bin/env bash
# Smoke test: verify all services in a running stack are healthy.
# Usage: bash tests/smoke/health-check.sh
# Called by `make test-smoke` which rebuilds and restarts the stack first.

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

pass() { echo -e "${GREEN}  [PASS]${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}  [FAIL]${NC} $1"; FAIL=$((FAIL + 1)); }
info() { echo -e "${YELLOW}$1${NC}"; }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

wait_for_url() {
  local url="$1"
  local label="$2"
  local max_attempts=20
  local attempt=1

  while [[ $attempt -le $max_attempts ]]; do
    if curl -sf --max-time 3 "$url" > /dev/null 2>&1; then
      return 0
    fi
    sleep 3
    ((attempt++))
  done

  return 1
}

wait_for_healthy() {
  local name_pattern="$1"
  local label="$2"
  local max_attempts=30   # up to 90s (30 × 3s) — enough for NestJS build + start
  local attempt=1
  local container

  info "  Waiting for $label..."
  while [[ $attempt -le $max_attempts ]]; do
    container=$(docker ps --filter "name=$name_pattern" --filter "health=healthy" --format "{{.Names}}" | head -1)
    if [[ -n "$container" ]]; then
      pass "$label is healthy ($container)"
      return 0
    fi
    sleep 3
    ((attempt++)) || true
  done

  # Timed out — show why
  local status
  status=$(docker ps -a --filter "name=$name_pattern" --format "{{.Names}} — {{.Status}}" | head -1)
  fail "$label — timed out waiting for healthy. Current status: ${status:-not found}"
  return 1
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

info "=== Stratum Smoke Tests ==="
echo ""

info "--- Waiting for all containers to be healthy ---"

wait_for_healthy "postgres" "PostgreSQL"
wait_for_healthy "hasura"   "Hasura"
wait_for_healthy "nestjs"   "NestJS"

echo ""
info "--- HTTP endpoints ---"

info "  Checking Hasura /healthz..."
if wait_for_url "http://localhost:8080/healthz" "Hasura"; then
  pass "Hasura /healthz → 200"
else
  fail "Hasura /healthz did not respond"
fi

info "  Checking NestJS /health (internal via docker exec)..."
nestjs_container=$(docker ps --filter "name=nestjs" --filter "health=healthy" --format "{{.Names}}" | head -1)
if [[ -n "$nestjs_container" ]]; then
  if docker exec "$nestjs_container" wget -qO- http://localhost:3000/health > /dev/null 2>&1; then
    pass "NestJS /health → 200 (via docker exec)"
  else
    fail "NestJS /health did not respond inside container"
  fi
else
  fail "NestJS container not healthy — cannot check /health"
fi

echo ""
info "--- Migration job ---"

migration_container=$(docker ps -a --filter "name=hasura_apply_migrations" --format "{{.Names}}" | head -1)
if [[ -n "$migration_container" ]]; then
  exit_code=$(docker inspect "$migration_container" --format "{{.State.ExitCode}}" 2>/dev/null || echo "unknown")
  if [[ "$exit_code" == "0" ]]; then
    pass "hasura-apply-migrations exited cleanly (exit code 0)"
  else
    fail "hasura-apply-migrations exited with code $exit_code"
    echo ""
    echo "  Last 20 lines of migration logs:"
    docker logs "$migration_container" 2>&1 | tail -20 | sed 's/^/    /'
  fi
else
  fail "hasura-apply-migrations container not found"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
info "=== Results: ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
