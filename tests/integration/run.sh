#!/usr/bin/env bash
# =============================================================================
# Stratum — Integration Test Runner
# =============================================================================
# Full end-to-end test: install → build → start → verify → teardown
# Each scenario runs in an isolated temp dir — repo root is never modified.
#
# Usage: bash tests/integration/run.sh [core|storage|dev|all]
#   core    — test minimal install (no storage)
#   storage — test full install (with storage)
#   dev     — test dev stack (hot reload, exposed ports, Hasura console)
#   all     — run core + storage scenarios (default)
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
# Test dir isolation
# Each scenario gets its own temp dir — a clean copy of the repo.
# Repo root is never modified.
# ---------------------------------------------------------------------------

TEST_DIR=""
ADMIN_SECRET=""
COMPOSE_EXTRA_FILES=()

setup_test_dir() {
  TEST_DIR=$(mktemp -d)
  info "  Copying project to isolated dir: $TEST_DIR"
  rsync -a \
    --exclude='.git' \
    --exclude='node_modules' \
    --exclude='tests/' \
    --exclude='.env' \
    --exclude='docker-compose.yml' \
    "$PROJECT_ROOT/" "$TEST_DIR/"
}

cleanup_test_dir() {
  if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
    info "  Removing test dir..."
    rm -rf "$TEST_DIR"
    TEST_DIR=""
  fi
}

# Tear down the docker stack that was started from TEST_DIR
# Uses COMPOSE_EXTRA_FILES for dev scenario overlay support
teardown() {
  info "  Tearing down stack..."
  if [[ -n "$TEST_DIR" && -f "$TEST_DIR/docker-compose.yml" ]]; then
    docker compose -f "$TEST_DIR/docker-compose.yml" "${COMPOSE_EXTRA_FILES[@]}" down -v --remove-orphans 2>/dev/null || true
  fi
}

# Safety net: always teardown + remove temp dir on unexpected exit
cleanup() {
  teardown
  cleanup_test_dir
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

reset_scenario() {
  SCENARIO_PASS=0
  SCENARIO_FAIL=0
  HASURA_SCHEMA_CACHE=""
  ADMIN_SECRET=""
  COMPOSE_EXTRA_FILES=()
}

# Load ADMIN_SECRET from the generated .env inside TEST_DIR
load_admin_secret() {
  if [[ -f "$TEST_DIR/.env" ]]; then
    ADMIN_SECRET=$(grep '^HASURA_GRAPHQL_ADMIN_SECRET=' "$TEST_DIR/.env" | cut -d= -f2-)
  else
    ADMIN_SECRET=""
  fi
}

# Wait for a container to report healthy (max 90s)
wait_for_healthy() {
  local pattern="$1" label="$2"
  local attempt=1 max=30 container

  info "  Waiting for $label..."
  while [[ $attempt -le $max ]]; do
    container=$(docker ps --filter "name=$pattern" --filter "health=healthy" --format "{{.Names}}" 2>/dev/null | head -1 || true)
    if [[ -n "$container" ]]; then
      pass "$label healthy ($container)"
      return 0
    fi
    sleep 3
    attempt=$((attempt + 1))
  done

  local status
  status=$(docker ps -a --filter "name=$pattern" --format "{{.Names}} — {{.Status}}" 2>/dev/null | head -1 || true)
  fail "$label — timed out. Status: ${status:-not found}"
  local cname
  cname=$(docker ps -a --filter "name=$pattern" --format "{{.Names}}" 2>/dev/null | head -1 || true)
  [[ -n "$cname" ]] && docker logs "$cname" 2>&1 | tail -10 | sed 's/^/    /'
  return 1
}

# Wait for migration container to exit, then check its exit code
check_migrations() {
  local attempt=0 max=20 status

  while [[ $attempt -lt $max ]]; do
    local cname
    cname=$(docker ps -a --filter "name=hasura_apply_migrations" --format "{{.Names}}" 2>/dev/null | head -1 || true)
    status=$(docker inspect "$cname" --format "{{.State.Status}}" 2>/dev/null || echo "")
    [[ "$status" == "exited" ]] && break
    sleep 3
    attempt=$((attempt + 1))
  done

  local cname
  cname=$(docker ps -a --filter "name=hasura_apply_migrations" --format "{{.Names}}" 2>/dev/null | head -1 || true)
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

# Run a GraphQL introspection against Hasura.
# Retries until schema has at least 1 non-builtin tracked table (avoids caching empty schema).
HASURA_SCHEMA_CACHE=""
fetch_hasura_schema() {
  if [[ -n "$HASURA_SCHEMA_CACHE" ]]; then
    echo "$HASURA_SCHEMA_CACHE"
    return
  fi
  local attempt=1 max=20 response fields
  while [[ $attempt -le $max ]]; do
    response=$(curl -sf --max-time 5 \
      -H "Content-Type: application/json" \
      -H "X-Hasura-Admin-Secret: $ADMIN_SECRET" \
      -d '{"query":"{ __schema { queryType { fields { name } } mutationType { fields { name } } } }"}' \
      http://localhost:8080/v1/graphql 2>/dev/null) || true

    fields=$(echo "$response" | python3 -c "
import json,sys
try:
  d=json.load(sys.stdin)
  qf=d['data']['__schema']['queryType']['fields']
  print(len([f for f in qf if not f['name'].startswith('__')]))
except:
  print(0)
" 2>/dev/null || echo "0")

    if [[ "$fields" -gt 0 ]]; then
      HASURA_SCHEMA_CACHE="$response"
      echo "$response"
      return 0
    fi
    sleep 3
    attempt=$((attempt + 1))
  done
  echo ""  # empty = schema never populated
}

# Check that a GraphQL query field (tracked table) EXISTS
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

# Check that a GraphQL query field does NOT exist
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

# Check NestJS endpoint responds 200 (via docker exec — port not exposed to host)
check_nestjs_endpoint() {
  local path="$1" label="$2"
  local cname
  cname=$(docker ps --filter "name=nestjs" --filter "health=healthy" --format "{{.Names}}" 2>/dev/null | head -1 || true)
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

# Check NestJS POST endpoint returns 404 (route not registered)
check_nestjs_action_absent() {
  local path="$1" label="$2"
  local cname code
  cname=$(docker ps --filter "name=nestjs" --filter "health=healthy" --format "{{.Names}}" 2>/dev/null | head -1 || true)
  if [[ -z "$cname" ]]; then
    fail "$label — NestJS container not healthy"
    return
  fi
  code=$(docker exec "$cname" sh -c "wget --server-response --post-data='{}' -O /dev/null http://localhost:3000$path 2>&1 | grep 'HTTP/' | awk '{print \$2}' | head -1")
  if [[ "$code" == "404" ]]; then
    pass "$label — $path correctly absent (404)"
  else
    fail "$label — $path should be absent, got HTTP $code"
  fi
}

# Check NestJS POST endpoint returns 400/401 (route registered but auth-gated)
check_nestjs_action_registered() {
  local path="$1" label="$2"
  local cname code
  cname=$(docker ps --filter "name=nestjs" --filter "health=healthy" --format "{{.Names}}" 2>/dev/null | head -1 || true)
  if [[ -z "$cname" ]]; then
    fail "$label — NestJS container not healthy"
    return
  fi
  code=$(docker exec "$cname" sh -c "wget --server-response --post-data='{}' -O /dev/null http://localhost:3000$path 2>&1 | grep 'HTTP/' | awk '{print \$2}' | head -1")
  if [[ "$code" == "401" || "$code" == "400" ]]; then
    pass "$label — $path registered (HTTP $code, auth-gated)"
  else
    fail "$label — $path returned unexpected HTTP $code (expected 400/401)"
  fi
}

# Check that a TCP port is open on localhost from the host
check_host_port() {
  local port="$1" label="$2"
  if nc -z localhost "$port" 2>/dev/null; then
    pass "$label — localhost:$port reachable from host"
  else
    fail "$label — localhost:$port not reachable from host"
  fi
}

# Check NestJS /health via host-exposed port (dev mode only)
check_nestjs_from_host() {
  if curl -sf --max-time 5 http://localhost:3000/health > /dev/null 2>&1; then
    pass "NestJS /health reachable from host (localhost:3000)"
  else
    fail "NestJS /health not reachable from host (localhost:3000)"
  fi
}

# Check Hasura console is enabled (returns 200, not 404)
check_hasura_console_enabled() {
  local code
  code=$(curl -so /dev/null -w "%{http_code}" --max-time 5 http://localhost:8080/console 2>/dev/null)
  if [[ "$code" == "200" ]]; then
    pass "Hasura console enabled (HTTP 200)"
  else
    fail "Hasura console not enabled (HTTP $code, expected 200)"
  fi
}

# Validate docker-compose.dev.yml merges cleanly with docker-compose.yml
check_dev_compose_syntax() {
  if docker compose \
      -f "$TEST_DIR/docker-compose.yml" \
      -f "$TEST_DIR/docker-compose.dev.yml" \
      config > /dev/null 2>&1; then
    pass "docker-compose.dev.yml merges cleanly"
  else
    fail "docker-compose.dev.yml has syntax/merge errors"
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

  # --- Setup: isolated temp dir ---
  section "Setup"
  setup_test_dir

  info "  Running install.sh (core-only, no storage)..."
  (cd "$TEST_DIR" && echo -e "test-project\nn\ny" | bash install.sh > /dev/null) || {
    fail "install.sh failed"
    cleanup
    return 1
  }
  pass "install.sh completed"

  # --- Verify install output ---
  section "Install output"
  [[ -f "$TEST_DIR/.env" ]]               && pass ".env created"               || fail ".env missing"
  [[ -f "$TEST_DIR/docker-compose.yml" ]] && pass "docker-compose.yml created" || fail "docker-compose.yml missing"
  ! grep -q "garage\|rustfs" "$TEST_DIR/docker-compose.yml" 2>/dev/null \
    && pass "No storage services in docker-compose.yml" \
    || fail "Storage services found in core-only docker-compose.yml"

  # --- Start stack ---
  section "Starting stack"
  (cd "$TEST_DIR" && docker compose up --build -d) || true
  echo ""

  load_admin_secret

  # --- Container health ---
  section "Container health"
  wait_for_healthy "postgres" "PostgreSQL"
  wait_for_healthy "hasura"   "Hasura"
  wait_for_healthy "nestjs"   "NestJS"

  # --- Migrations ---
  section "Migrations"
  check_migrations

  # --- DB / Hasura schema ---
  section "Database schema (via Hasura GraphQL)"
  check_hasura_field_exists "users" "Core: users table tracked"
  check_hasura_field_absent "files" "Core: files table absent"

  # --- Hasura actions ---
  section "Hasura actions"
  check_hasura_mutation_absent "requestUploadUrl" "Core: requestUploadUrl absent"
  check_hasura_mutation_absent "confirmUpload"    "Core: confirmUpload absent"
  check_hasura_mutation_absent "deleteFile"       "Core: deleteFile absent"

  # --- NestJS endpoints ---
  section "NestJS endpoints"
  check_nestjs_endpoint      "/health"                      "NestJS: GET /health"
  check_nestjs_action_absent "/actions/request-upload-url" "NestJS: storage actions absent"

  # --- Teardown ---
  section "Teardown"
  teardown
  cleanup_test_dir
  pass "Stack torn down, temp dir removed"

  # --- Scenario summary ---
  echo ""
  if [[ $SCENARIO_FAIL -eq 0 ]]; then
    echo -e "${GREEN}  ✓ SCENARIO PASSED: ${SCENARIO_PASS} checks${NC}"
  else
    echo -e "${RED}  ✗ SCENARIO FAILED: ${SCENARIO_PASS} passed, ${SCENARIO_FAIL} failed${NC}"
  fi
}

# ---------------------------------------------------------------------------
# Scenario: Full install (with storage)
# ---------------------------------------------------------------------------

run_storage_scenario() {
  reset_scenario
  echo ""
  echo -e "${BLUE}============================================================${NC}"
  echo -e "${BLUE}  SCENARIO: Full install (with storage)${NC}"
  echo -e "${BLUE}============================================================${NC}"

  # --- Setup: isolated temp dir ---
  section "Setup"
  setup_test_dir

  info "  Running install.sh (with storage enabled)..."
  (cd "$TEST_DIR" && echo -e "test-project\ny\ny" | bash install.sh > /dev/null) || {
    fail "install.sh failed"
    cleanup
    return 1
  }
  pass "install.sh completed"

  # --- Verify install output ---
  section "Install output"
  [[ -f "$TEST_DIR/.env" ]]               && pass ".env created"               || fail ".env missing"
  [[ -f "$TEST_DIR/docker-compose.yml" ]] && pass "docker-compose.yml created" || fail "docker-compose.yml missing"
  grep -q "rustfs" "$TEST_DIR/docker-compose.yml" 2>/dev/null \
    && pass "Storage service (rustfs) in docker-compose.yml" \
    || fail "Storage service missing from docker-compose.yml"

  # --- Start stack ---
  section "Starting stack"
  (cd "$TEST_DIR" && docker compose up --build -d) || true
  echo ""

  load_admin_secret

  # --- Container health ---
  section "Container health"
  wait_for_healthy "postgres" "PostgreSQL"
  wait_for_healthy "hasura"   "Hasura"
  wait_for_healthy "nestjs"   "NestJS"
  wait_for_healthy "rustfs"   "RustFS"

  # --- Migrations ---
  section "Migrations"
  check_migrations

  # --- DB / Hasura schema ---
  section "Database schema (via Hasura GraphQL)"
  check_hasura_field_exists "users" "Storage: users table tracked"
  check_hasura_field_exists "files" "Storage: files table tracked"

  # --- Hasura actions ---
  section "Hasura actions"
  check_hasura_mutation_exists "requestUploadUrl" "Storage: requestUploadUrl exists"
  check_hasura_mutation_exists "confirmUpload"    "Storage: confirmUpload exists"
  check_hasura_mutation_exists "deleteFile"       "Storage: deleteFile exists"

  # --- NestJS endpoints ---
  section "NestJS endpoints"
  check_nestjs_endpoint         "/health"                      "NestJS: GET /health"
  check_nestjs_action_registered "/actions/request-upload-url" "NestJS: request-upload-url registered"
  check_nestjs_action_registered "/actions/confirm-upload"     "NestJS: confirm-upload registered"
  check_nestjs_action_registered "/actions/delete-file"        "NestJS: delete-file registered"

  # --- Teardown ---
  section "Teardown"
  teardown
  cleanup_test_dir
  pass "Stack torn down, temp dir removed"

  # --- Scenario summary ---
  echo ""
  if [[ $SCENARIO_FAIL -eq 0 ]]; then
    echo -e "${GREEN}  ✓ SCENARIO PASSED: ${SCENARIO_PASS} checks${NC}"
  else
    echo -e "${RED}  ✗ SCENARIO FAILED: ${SCENARIO_PASS} passed, ${SCENARIO_FAIL} failed${NC}"
  fi
}

# ---------------------------------------------------------------------------
# Scenario: Dev stack (hot reload + exposed ports)
# ---------------------------------------------------------------------------

run_dev_scenario() {
  reset_scenario
  echo ""
  echo -e "${BLUE}============================================================${NC}"
  echo -e "${BLUE}  SCENARIO: Dev stack (hot reload + exposed ports)${NC}"
  echo -e "${BLUE}============================================================${NC}"

  # --- Setup: isolated temp dir ---
  section "Setup"
  setup_test_dir

  info "  Running install.sh (core-only, dev scenario)..."
  (cd "$TEST_DIR" && echo -e "test-project\nn\ny" | bash install.sh > /dev/null) || {
    fail "install.sh failed"
    cleanup
    return 1
  }
  pass "install.sh completed"

  # Use dev overlay for teardown
  COMPOSE_EXTRA_FILES=("-f" "$TEST_DIR/docker-compose.dev.yml")

  # --- Verify install output ---
  section "Install output"
  [[ -f "$TEST_DIR/.env" ]]               && pass ".env created"               || fail ".env missing"
  [[ -f "$TEST_DIR/docker-compose.yml" ]] && pass "docker-compose.yml created" || fail "docker-compose.yml missing"
  [[ -f "$TEST_DIR/hasura/.env" ]]        && pass "hasura/.env created"        || fail "hasura/.env missing"
  grep -q "^HASURA_GRAPHQL_ADMIN_SECRET=" "$TEST_DIR/hasura/.env" 2>/dev/null \
    && pass "hasura/.env has admin secret" \
    || fail "hasura/.env missing admin secret"

  # --- Compose validation (before starting containers) ---
  section "Compose validation"
  check_dev_compose_syntax

  # --- Start dev stack ---
  section "Starting dev stack"
  (cd "$TEST_DIR" && docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build -d) || true
  echo ""

  load_admin_secret

  # --- Container health ---
  section "Container health"
  wait_for_healthy "postgres" "PostgreSQL"
  wait_for_healthy "hasura"   "Hasura"
  wait_for_healthy "nestjs"   "NestJS"

  # --- Migrations ---
  section "Migrations"
  check_migrations

  # --- Host port exposure ---
  section "Host port exposure"
  check_host_port 5432 "PostgreSQL"
  check_nestjs_from_host

  # --- Hasura dev mode ---
  section "Hasura dev mode"
  check_hasura_console_enabled

  # --- Teardown ---
  section "Teardown"
  teardown
  cleanup_test_dir
  pass "Stack torn down, temp dir removed"

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
  storage)
    run_storage_scenario
    ;;
  dev)
    run_dev_scenario
    ;;
  all)
    run_core_scenario
    run_storage_scenario
    ;;
  *)
    echo "Usage: $0 [core|storage|dev|all]"
    exit 1
    ;;
esac

# Disable trap (already cleaned up)
trap - EXIT

echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}  Total: ${PASS} passed, ${FAIL} failed${NC}"
echo -e "${BLUE}============================================================${NC}"

[[ $FAIL -eq 0 ]]
