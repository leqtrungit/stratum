#!/usr/bin/env bash
# Install script tests: verify bootstrap.sh produces correct output.
# Runs in an isolated temp directory — no Docker required.
# Usage: bash tests/scripts/test-install.sh

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

setup_tmp() {
  TMP_DIR=$(mktemp -d)
  trap "rm -rf $TMP_DIR" EXIT
}

assert_file_exists() {
  local file="$1" label="$2"
  if [[ -f "$TMP_DIR/$file" ]]; then
    pass "$label — $file exists"
  else
    fail "$label — $file missing"
  fi
}

assert_file_not_exists() {
  local file="$1" label="$2"
  if [[ ! -f "$TMP_DIR/$file" ]]; then
    pass "$label — $file correctly absent"
  else
    fail "$label — $file should not exist"
  fi
}

assert_dir_not_exists() {
  local dir="$1" label="$2"
  if [[ ! -d "$TMP_DIR/$dir" ]]; then
    pass "$label — $dir correctly absent"
  else
    fail "$label — $dir should not exist"
  fi
}

assert_file_contains() {
  local file="$1" pattern="$2" label="$3"
  if grep -q "$pattern" "$TMP_DIR/$file" 2>/dev/null; then
    pass "$label"
  else
    fail "$label — pattern '$pattern' not found in $file"
  fi
}

assert_file_not_contains() {
  local file="$1" pattern="$2" label="$3"
  if ! grep -q "$pattern" "$TMP_DIR/$file" 2>/dev/null; then
    pass "$label"
  else
    fail "$label — '$pattern' should not be in $file"
  fi
}

assert_secret_unique() {
  local key="$1" run1="$2" run2="$3" label="$4"
  val1=$(grep "^$key=" "$run1" | cut -d= -f2-)
  val2=$(grep "^$key=" "$run2" | cut -d= -f2-)
  if [[ -n "$val1" && "$val1" != "$val2" ]]; then
    pass "$label — $key is unique across runs"
  else
    fail "$label — $key is identical across runs (not random): '$val1'"
  fi
}

# ---------------------------------------------------------------------------
# Test: Core-only setup (STORAGE_ENABLED=n)
# ---------------------------------------------------------------------------

run_bootstrap_core() {
  local dir="$1"
  cd "$dir"
  # Copy project files that bootstrap.sh would normally download
  cp -R "$PROJECT_ROOT/nestjs" .
  cp -R "$PROJECT_ROOT/hasura" .
  cp -R "$PROJECT_ROOT/.template" . 2>/dev/null || true
  cp "$PROJECT_ROOT/docker-compose.base.yml" .
  cp "$PROJECT_ROOT/docker-compose.storage.yml" . 2>/dev/null || true
  cp "$PROJECT_ROOT/.env.example" .

  # Run bootstrap logic (install portion only — skip download step)
  # We source the relevant section by running install.sh directly
  PROJECT_NAME="test-project" ENABLE_STORAGE="n" bash "$PROJECT_ROOT/bootstrap.sh" <<< $'test-project\nn' 2>/dev/null || true
}

# ---------------------------------------------------------------------------

info "=== Stratum Install Tests ==="
echo ""

# --- Test Suite 1: Core-only ---
info "--- Suite 1: Core-only setup (STORAGE_ENABLED=n) ---"

setup_tmp
TMP_CORE="$TMP_DIR/core"
mkdir -p "$TMP_CORE"

(cd "$TMP_CORE" && \
  cp -R "$PROJECT_ROOT/nestjs" . && \
  cp -R "$PROJECT_ROOT/hasura" . && \
  cp -R "$PROJECT_ROOT/.env.example" . && \
  cp "$PROJECT_ROOT/docker-compose.base.yml" . && \
  [[ -d "$PROJECT_ROOT/.template" ]] && cp -R "$PROJECT_ROOT/.template" . || true && \
  [[ -f "$PROJECT_ROOT/docker-compose.storage.yml" ]] && cp "$PROJECT_ROOT/docker-compose.storage.yml" . || true
) 2>/dev/null

# Run install.sh in core-only mode
if (cd "$TMP_CORE" && echo -e "test-project\nn" | bash "$PROJECT_ROOT/install.sh" > /dev/null 2>&1); then
  TMP_DIR="$TMP_CORE"

  assert_file_exists ".env"                   "1.1 .env is created"
  assert_file_exists "docker-compose.yml"     "1.1 docker-compose.yml is created"

  assert_file_not_contains "docker-compose.yml" "garage"  "1.1 Storage absent from docker-compose.yml"
  assert_file_not_contains "docker-compose.yml" "rustfs"  "1.1 RustFS absent from docker-compose.yml"

  assert_file_contains ".env" "PROJECT_NAME=test-project" "1.1 PROJECT_NAME set correctly"
  assert_file_contains ".env" "STORAGE_ENABLED=false"     "1.1 STORAGE_ENABLED=false"
else
  fail "1.1 install.sh failed to run in core-only mode"
fi

echo ""

# --- Test Suite 2: Secret uniqueness ---
info "--- Suite 2: Secrets are unique per run ---"

TMP_RUN1=$(mktemp -d)
TMP_RUN2=$(mktemp -d)
trap "rm -rf $TMP_RUN1 $TMP_RUN2" EXIT 2>/dev/null || true

for dir in "$TMP_RUN1" "$TMP_RUN2"; do
  (cd "$dir" && \
    cp -R "$PROJECT_ROOT/nestjs" . && \
    cp -R "$PROJECT_ROOT/hasura" . && \
    cp "$PROJECT_ROOT/.env.example" . && \
    cp "$PROJECT_ROOT/docker-compose.base.yml" . && \
    [[ -f "$PROJECT_ROOT/docker-compose.storage.yml" ]] && cp "$PROJECT_ROOT/docker-compose.storage.yml" . || true && \
    echo -e "my-project\nn" | bash "$PROJECT_ROOT/install.sh" > /dev/null 2>&1
  ) 2>/dev/null || true
done

if [[ -f "$TMP_RUN1/.env" && -f "$TMP_RUN2/.env" ]]; then
  assert_secret_unique "HASURA_GRAPHQL_ADMIN_SECRET" "$TMP_RUN1/.env" "$TMP_RUN2/.env" "2.1"
  assert_secret_unique "HASURA_EVENT_SECRET"         "$TMP_RUN1/.env" "$TMP_RUN2/.env" "2.1"
  assert_secret_unique "POSTGRES_PASSWORD"           "$TMP_RUN1/.env" "$TMP_RUN2/.env" "2.1"
else
  fail "2.1 Could not run two separate installs to compare secrets"
fi

rm -rf "$TMP_RUN1" "$TMP_RUN2"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
info "=== Results: ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
