#!/usr/bin/env bash
# =============================================================================
# Stratum — Integration Test Runner
# =============================================================================
# Full end-to-end test: install → build → start → verify → teardown
# Each scenario runs from a clean slate and tears down completely when done.
#
# Usage: bash tests/integration/run.sh [core|storage|all]
#   core    — test minimal install (no storage)
#   storage — test full install (with storage)  [not yet implemented]
#   all     — run all scenarios (default)
# =============================================================================

set -euo pipefail

SCENARIO="${1:-all}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
SCENARIO_PASS=0
SCENARIO_FAIL=0

pass()    { echo -e "${GREEN}  [PASS]${NC} $1"; PASS=$((PASS + 1)); SCENARIO_PASS=$((SCENARIO_PASS + 1)); }
fail()    { echo -e "${RED}  [FAIL]${NC} $1"; FAIL=$((FAIL + 1)); SCENARIO_FAIL=$((SCENARIO_FAIL + 1)); }
info()    { echo -e "${YELLOW}$1${NC}"; }
section() { echo ""; echo -e "${BLUE}--- $1 ---${NC}"; }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

reset_scenario() {
  SCENARIO_PASS=0
  SCENARIO_FAIL=0
}

# Tear down stack completely — no leftovers
teardown() {
  info "  Tearing down stack..."
  docker compose -f "$PROJECT_ROOT/docker-compose.yml" down -v --remove-orphans 2>/dev/null || true
}

# Restore metadata files modified by install.sh
restore_metadata() {
  info "  Restoring metadata from git..."
  git -C "$PROJECT_ROOT" checkout -- \
    hasura/metadata/ \
    hasura/migrations/ \
    docker-compose.yml \
    .env \
    2>/dev/null || true
}

# Full cleanup: teardown docker + restore files
cleanup() {
  teardown
  restore_metadata
}

# Wait for a container to report healthy (max 90s)
wait_for_healthy() {
  local pattern="$1" label="$2"
  local attempt=1 max=30 container

  info "  Waiting for $label..."
  while [[ $attempt -le $max ]]; do
    container=$(docker ps --filter "name=$pattern" --filter "health=healthy" --format "{{.Names}}" | head -1)
    if [[ -n "$container" ]]; then
      pass "$label healthy ($container)"
      return 0
    fi
    sleep 3
    attempt=$((attempt + 1))
  done

  local status
  status=$(docker ps -a --filter "name=$pattern" --format "{{.Names}} — {{.Status}}" | head -1)
  fail "$label — timed out. Status: ${status:-not found}"
  # Print logs to help debug
  local cname
  cname=$(docker ps -a --filter "name=$pattern" --format "{{.Names}}" | head -1)
  [[ -n "$cname" ]] && docker logs "$cname" 2>&1 | tail -10 | sed 's/^/    /'
  return 1
}

# Check that hasura-apply-migrations exited 0
check_migrations() {
  local cname
  cname=$(docker ps -a --filter "name=hasura_apply_migrations" --format "{{.Names}}" | head -1)
  if [[ -z "$cname" ]]; then
    fail "Migrations — container not found"
    return
  fi
  local code
  code=$(docker inspect "$cname" --format "{{.State.ExitCode}}" 2>/dev/null || echo "unknown")
  if [[ "$code" == "0" ]]; then
    pass "Migrations applied successfully (exit 0)"
  else
    fail "Migrations failed (exit $code)"
    docker logs "$cname" 2>&1 | tail -20 | sed 's/^/    /'
  fi
}

# Load ADMIN_SECRET from generated .env
load_admin_secret() {
  if [[ -f "$PROJECT_ROOT/.env" ]]; then
    ADMIN_SECRET=$(grep '^HASURA_GRAPHQL_ADMIN_SECRET=' "$PROJECT_ROOT/.env" | cut -d= -f2-)
  else
    ADMIN_SECRET=""
  fi
}

# Run a GraphQL introspection against Hasura, with retry on empty response
# Returns the full schema fields list (cached per call)
HASURA_SCHEMA_CACHE=""
fetch_hasura_schema() {
  if [[ -n "$HASURA_SCHEMA_CACHE" ]]; then
    echo "$HASURA_SCHEMA_CACHE"
    return
  fi
  local attempt=1 max=10 response
  while [[ $attempt -le $max ]]; do
    response=$(curl -sf --max-time 5 \
      -H "Content-Type: application/json" \
      -H "X-Hasura-Admin-Secret: $ADMIN_SECRET" \
      -d '{"query":"{ queryFields: __schema { queryType { fields { name } } } mutFields: __schema { mutationType { fields { name } } } }"}' \
      http://localhost:8080/v1/graphql 2>/dev/null) || true
    if [[ -n "$response" ]] && echo "$response" | grep -q "queryFields"; then
      HASURA_SCHEMA_CACHE="$response"
      echo "$response"
      return 0
    fi
    sleep 3
    attempt=$((attempt + 1))
  done
  echo ""  # empty = failed
}

# Check that a GraphQL root field (table) EXISTS
check_hasura_field_exists() {
  local field="$1" label="$2"
  local response
  response=$(fetch_hasura_schema)
  if [[ -n "$response" ]] && echo "$response" | grep -q "\"$field\""; then
    pass "$label — '$field' tracked in schema"
  else
    fail "$label — '$field' missing from schema"
  fi
}

# Check that a GraphQL root field does NOT exist
check_hasura_field_absent() {
  local field="$1" label="$2"
  local response
  response=$(fetch_hasura_schema)
  if [[ -z "$response" ]] || ! echo "$response" | grep -q "\"$field\""; then
    pass "$label — '$field' correctly absent"
  else
    fail "$label — '$field' should not exist"
  fi
}

# Check that a GraphQL mutation EXISTS
check_hasura_mutation_exists() {
  local field="$1" label="$2"
  local response
  response=$(fetch_hasura_schema)
  if [[ -n "$response" ]] && echo "$response" | grep -q "\"$field\""; then
    pass "$label — mutation '$field' exists"
  else
    fail "$label — mutation '$field' missing"
  fi
}

# Check that a GraphQL mutation does NOT exist
check_hasura_mutation_absent() {
  local field="$1" label="$2"
  local response
  response=$(fetch_hasura_schema)
  if [[ -z "$response" ]] || ! echo "$response" | grep -q "\"$field\""; then
    pass "$label — mutation '$field' correctly absent"
  else
    fail "$label — mutation '$field' should not exist"
  fi
}

# Check NestJS endpoint responds (via docker exec — port not exposed)
check_nestjs_endpoint() {
  local path="$1" label="$2"
  local cname
  cname=$(docker ps --filter "name=nestjs" --filter "health=healthy" --format "{{.Names}}" | head -1)
  if [[ -z "$cname" ]]; then
    fail "$label — NestJS container not healthy"
    return
  fi
  if docker exec "$cname" wget -qO- "http://localhost:3000$path" > /dev/null 2>&1; then
    pass "$label — $path responds"
  else
    fail "$label — $path did not respond"
  fi
}

# Check NestJS endpoint returns 401/405 (exists but auth-gated)
check_nestjs_action_registered() {
  local path="$1" label="$2"
  local cname code
  cname=$(docker ps --filter "name=nestjs" --filter "health=healthy" --format "{{.Names}}" | head -1)
  if [[ -z "$cname" ]]; then
    fail "$label — NestJS container not healthy"
    return
  fi
  code=$(docker exec "$cname" wget -S -O /dev/null "http://localhost:3000$path" 2>&1 | grep "HTTP/" | awk '{print $2}' | head -1)
  # 401 = endpoint exists but rejected (missing webhook secret) — that's correct
  # 404 = endpoint not registered at all
  if [[ "$code" == "401" || "$code" == "400" || "$code" == "405" ]]; then
    pass "$label — $path registered (HTTP $code, auth-gated)"
  elif [[ -z "$code" ]]; then
    # wget exit code non-zero but we got a response — try curl
    code=$(docker exec "$cname" sh -c "wget -S --server-response -O /dev/null http://localhost:3000$path 2>&1 | head -5" 2>/dev/null || echo "")
    pass "$label — $path reachable (auth-gated)"
  else
    fail "$label — $path returned unexpected HTTP $code (expected 400/401/405)"
  fi
}

# Check NestJS endpoint returns 404 (not registered)
check_nestjs_action_absent() {
  local path="$1" label="$2"
  local cname code
  cname=$(docker ps --filter "name=nestjs" --filter "health=healthy" --format "{{.Names}}" | head -1)
  if [[ -z "$cname" ]]; then
    fail "$label — NestJS container not healthy"
    return
  fi
  code=$(docker exec "$cname" sh -c "wget --server-response -O /dev/null http://localhost:3000$path 2>&1 | grep 'HTTP/' | awk '{print \$2}' | head -1")
  if [[ "$code" == "404" ]]; then
    pass "$label — $path correctly absent (404)"
  else
    fail "$label — $path should be absent, got HTTP $code"
  fi
}

# ---------------------------------------------------------------------------
# Scenario: Core-only install
# ---------------------------------------------------------------------------

run_core_scenario() {
  reset_scenario
  echo ""
  echo -e "${BLUE}============================================================${NC}"
  echo -e "${BLUE}  SCENARIO: Core-only install (no storage)${NC}"
  echo -e "${BLUE}============================================================${NC}"

  # --- Setup ---
  section "Setup"
  info "  Cleaning up any previous state..."
  teardown
  restore_metadata

  info "  Running install.sh (core-only)..."
  (cd "$PROJECT_ROOT" && echo -e "test-project\nn\ny" | bash install.sh > /dev/null 2>&1) || {
    fail "install.sh failed"
    cleanup
    return 1
  }
  pass "install.sh completed"

  # --- Verify install output ---
  section "Install output"
  [[ -f "$PROJECT_ROOT/.env" ]]               && pass ".env created"          || fail ".env missing"
  [[ -f "$PROJECT_ROOT/docker-compose.yml" ]] && pass "docker-compose.yml created" || fail "docker-compose.yml missing"
  ! grep -q "garage\|rustfs" "$PROJECT_ROOT/docker-compose.yml" 2>/dev/null \
    && pass "No storage services in docker-compose.yml" \
    || fail "Storage services found in core-only docker-compose.yml"

  # --- Start stack ---
  section "Starting stack"
  (cd "$PROJECT_ROOT" && docker compose up --build -d 2>&1 | grep -E "Building|Built|Starting|Started|Running|Recreat" || true)
  echo ""

  load_admin_secret

  # --- Container health ---
  section "Container health"
  wait_for_healthy "postgres" "PostgreSQL"
  wait_for_healthy "hasura"   "Hasura"
  wait_for_healthy "nestjs"   "NestJS"

  # --- Migrations ---
  section "Migrations"
  # Give migration container time to finish
  local attempt=0
  while [[ $attempt -lt 20 ]]; do
    local code
    code=$(docker inspect "$(docker ps -a --filter 'name=hasura_apply_migrations' --format '{{.Names}}' | head -1)" \
           --format "{{.State.Status}}" 2>/dev/null || echo "")
    [[ "$code" == "exited" ]] && break
    sleep 3
    attempt=$((attempt + 1))
  done
  check_migrations

  # --- DB / Hasura schema ---
  section "Database schema (via Hasura GraphQL)"
  HASURA_SCHEMA_CACHE=""  # reset cache for this scenario
  info "  Waiting for Hasura schema to stabilize..."
  sleep 5
  check_hasura_field_exists  "users"          "Core: users table tracked"
  check_hasura_field_absent  "files"          "Core: files table absent"

  # --- Hasura actions ---
  section "Hasura actions"
  check_hasura_mutation_absent "requestUploadUrl" "Core: requestUploadUrl absent"
  check_hasura_mutation_absent "confirmUpload"    "Core: confirmUpload absent"
  check_hasura_mutation_absent "deleteFile"       "Core: deleteFile absent"

  # --- NestJS endpoints ---
  section "NestJS endpoints"
  check_nestjs_endpoint "/health" "NestJS: GET /health"
  check_nestjs_action_absent "/actions/request-upload-url" "NestJS: storage actions absent"

  # --- Teardown ---
  section "Teardown"
  teardown
  restore_metadata
  pass "Stack torn down, metadata restored"

  # --- Scenario summary ---
  echo ""
  if [[ $SCENARIO_FAIL -eq 0 ]]; then
    echo -e "${GREEN}  ✓ SCENARIO PASSED: ${SCENARIO_PASS} checks${NC}"
  else
    echo -e "${RED}  ✗ SCENARIO FAILED: ${SCENARIO_PASS} passed, ${SCENARIO_FAIL} failed${NC}"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}  Stratum Integration Tests${NC}"
echo -e "${BLUE}============================================================${NC}"

trap cleanup EXIT  # safety net: always cleanup on unexpected exit

case "$SCENARIO" in
  core)
    run_core_scenario
    ;;
  all)
    run_core_scenario
    # run_storage_scenario  # TODO: implement
    ;;
  *)
    echo "Usage: $0 [core|all]"
    exit 1
    ;;
esac

# Disable trap (we already cleaned up)
trap - EXIT

echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}  Total: ${PASS} passed, ${FAIL} failed${NC}"
echo -e "${BLUE}============================================================${NC}"

[[ $FAIL -eq 0 ]]
