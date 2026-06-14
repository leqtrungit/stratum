#!/usr/bin/env bash
# Install script tests: verify install.sh produces correct output.
# Runs in isolated temp directories — no Docker required.
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

# Copy only what install.sh needs — never copy node_modules
setup_install_dir() {
  local target="$1"
  mkdir -p "$target"
  cp -R "$PROJECT_ROOT/hasura" "$target/"
  cp "$PROJECT_ROOT/.env.example" "$target/"
  cp "$PROJECT_ROOT/docker-compose.base.yml" "$target/"
  [[ -f "$PROJECT_ROOT/docker-compose.storage.yml" ]] && \
    cp "$PROJECT_ROOT/docker-compose.storage.yml" "$target/" || true
}

run_install() {
  local dir="$1" answers="$2"
  # Verify the dir has required files before running install — safety net
  if [[ ! -f "$dir/.env.example" || ! -d "$dir/hasura" || ! -f "$dir/docker-compose.base.yml" ]]; then
    echo "test setup failed: required files missing in $dir" >&2
    return 1
  fi
  (cd "$dir" && echo -e "$answers" | bash "$PROJECT_ROOT/install.sh" > /dev/null 2>&1)
}

assert_file_exists() {
  local dir="$1" file="$2" label="$3"
  if [[ -f "$dir/$file" ]]; then
    pass "$label — $file exists"
  else
    fail "$label — $file missing"
  fi
}

assert_file_contains() {
  local dir="$1" file="$2" pattern="$3" label="$4"
  if grep -q "$pattern" "$dir/$file" 2>/dev/null; then
    pass "$label"
  else
    fail "$label — pattern '$pattern' not found in $file"
  fi
}

assert_file_not_contains() {
  local dir="$1" file="$2" pattern="$3" label="$4"
  if ! grep -q "$pattern" "$dir/$file" 2>/dev/null; then
    pass "$label"
  else
    fail "$label — '$pattern' should not be in $file"
  fi
}

assert_secret_unique() {
  local key="$1" env1="$2" env2="$3" label="$4"
  local val1 val2
  val1=$(grep "^$key=" "$env1" | cut -d= -f2-)
  val2=$(grep "^$key=" "$env2" | cut -d= -f2-)
  if [[ -n "$val1" && "$val1" != "$val2" ]]; then
    pass "$label — $key is unique across runs"
  else
    fail "$label — $key identical across runs (not random)"
  fi
}

# ---------------------------------------------------------------------------
# Suite 1: Core-only setup
# ---------------------------------------------------------------------------

info "=== Stratum Install Tests ==="
echo ""
info "--- Suite 1: Core-only setup (STORAGE_ENABLED=n) ---"

TMP1=$(mktemp -d)
trap "rm -rf $TMP1" EXIT

setup_install_dir "$TMP1"

if run_install "$TMP1" "test-project\nn\ny"; then
  assert_file_exists     "$TMP1" ".env"               "1.1 .env is created"
  assert_file_exists     "$TMP1" "docker-compose.yml" "1.1 docker-compose.yml is created"
  assert_file_not_contains "$TMP1" "docker-compose.yml" "garage" "1.1 Storage absent from docker-compose.yml"
  assert_file_not_contains "$TMP1" "docker-compose.yml" "rustfs" "1.1 RustFS absent from docker-compose.yml"
  assert_file_contains   "$TMP1" ".env" "PROJECT_NAME=test-project" "1.1 PROJECT_NAME set correctly"
  assert_file_contains   "$TMP1" ".env" "STORAGE_ENABLED=false"     "1.1 STORAGE_ENABLED=false"
else
  fail "1.1 install.sh failed to run in core-only mode"
fi

echo ""

# ---------------------------------------------------------------------------
# Suite 2: Secrets are unique per run
# ---------------------------------------------------------------------------

info "--- Suite 2: Secrets are unique per run ---"

TMP2A=$(mktemp -d)
TMP2B=$(mktemp -d)
trap "rm -rf $TMP1 $TMP2A $TMP2B" EXIT

setup_install_dir "$TMP2A"
setup_install_dir "$TMP2B"

run_install "$TMP2A" "my-project\nn\ny" || true
run_install "$TMP2B" "my-project\nn\ny" || true

if [[ -f "$TMP2A/.env" && -f "$TMP2B/.env" ]]; then
  assert_secret_unique "HASURA_GRAPHQL_ADMIN_SECRET" "$TMP2A/.env" "$TMP2B/.env" "2.1"
  assert_secret_unique "HASURA_EVENT_SECRET"         "$TMP2A/.env" "$TMP2B/.env" "2.1"
  assert_secret_unique "POSTGRES_PASSWORD"           "$TMP2A/.env" "$TMP2B/.env" "2.1"
else
  fail "2.1 Could not run two installs to compare secrets"
fi

# ---------------------------------------------------------------------------
# Suite 3: Input validation & normalization
# ---------------------------------------------------------------------------

echo ""
info "--- Suite 3: Input validation & normalization ---"

TMP3=$(mktemp -d)
trap "rm -rf $TMP1 $TMP2A $TMP2B $TMP3" EXIT

setup_install_dir "$TMP3"

# Project name with uppercase + spaces → should be normalized to lowercase-with-hyphens
if run_install "$TMP3" "My Cool App\nn\ny"; then
  assert_file_contains "$TMP3" ".env" "PROJECT_NAME=my-cool-app" "3.1 Project name normalized (uppercase + spaces)"
else
  fail "3.1 install.sh failed with mixed-case project name"
fi

# ---------------------------------------------------------------------------
# Suite 4: hasura/.env generation
# ---------------------------------------------------------------------------

echo ""
info "--- Suite 4: hasura/.env generation ---"

TMP4=$(mktemp -d)
trap "rm -rf $TMP1 $TMP2A $TMP2B $TMP3 $TMP4" EXIT

setup_install_dir "$TMP4"

if run_install "$TMP4" "test-project\nn\ny"; then
  assert_file_exists   "$TMP4" "hasura/.env" "4.1 hasura/.env created"
  assert_file_contains "$TMP4" "hasura/.env" "HASURA_GRAPHQL_ADMIN_SECRET=" "4.1 hasura/.env has admin secret"

  SECRET_ENV=$(grep '^HASURA_GRAPHQL_ADMIN_SECRET=' "$TMP4/.env"          | cut -d= -f2-)
  SECRET_HASURA=$(grep '^HASURA_GRAPHQL_ADMIN_SECRET=' "$TMP4/hasura/.env" | cut -d= -f2-)
  if [[ -n "$SECRET_ENV" && "$SECRET_ENV" == "$SECRET_HASURA" ]]; then
    pass "4.1 hasura/.env secret matches .env"
  else
    fail "4.1 hasura/.env secret does not match .env"
  fi
else
  fail "4.1 install.sh failed (suite 4)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
info "=== Results: ${PASS} passed, ${FAIL} failed ==="

[[ $FAIL -eq 0 ]]
