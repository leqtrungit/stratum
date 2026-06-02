#!/usr/bin/env bash
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/leqtrungit/stratum/main/bootstrap.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/leqtrungit/stratum/main/bootstrap.sh | bash -s -- my-project

set -euo pipefail

REPO="leqtrungit/stratum"
DEFAULT_DIR="my-project"

# Files/dirs that belong to Stratum's own development — not part of a user project.
STRATUM_INTERNAL=(
  .agents          # AI agent skills and rules
  .claude          # Claude Code session data
  .github          # Stratum's CI workflows (depend on tests/ which is also removed)
  AGENTS.md        # AI orchestration instructions
  CLAUDE.md        # Claude Code project config
  bootstrap.sh     # Self-remove: used once to scaffold, not needed after
  plan.md          # Stratum project planning
  skills-lock.json # Claude Code internal
  tasks            # Stratum task tracking
  tests            # Stratum integration tests (stratum-specific, not for user projects)
)

# ── Project directory ─────────────────────────────────────────────────────────
# stdin may be the curl pipe, so always read from /dev/tty for user prompts.

if [ -n "${1:-}" ]; then
  PROJECT_DIR="$1"
else
  printf "Project directory name [%s]: " "$DEFAULT_DIR" >/dev/tty
  read -r PROJECT_DIR </dev/tty
  PROJECT_DIR="${PROJECT_DIR:-$DEFAULT_DIR}"
fi

if [ -d "$PROJECT_DIR" ]; then
  echo "Error: directory '$PROJECT_DIR' already exists." >&2
  exit 1
fi

# ── Resolve version ───────────────────────────────────────────────────────────
# Prefer the latest GitHub release tag; fall back to main.

LATEST_TAG=$(
  curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
    | grep '"tag_name"' | cut -d'"' -f4 || true
)

if [ -n "${LATEST_TAG:-}" ]; then
  TARBALL_URL="https://github.com/$REPO/archive/refs/tags/$LATEST_TAG.tar.gz"
  echo "Downloading Stratum $LATEST_TAG..."
else
  TARBALL_URL="https://github.com/$REPO/archive/refs/heads/main.tar.gz"
  echo "Downloading Stratum (latest from main)..."
fi

# ── Download & extract ────────────────────────────────────────────────────────

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

curl -fsSL "$TARBALL_URL" | tar -xz -C "$TMP_DIR"

EXTRACTED=$(ls "$TMP_DIR")
mv "$TMP_DIR/$EXTRACTED" "$PROJECT_DIR"

# ── Remove Stratum-internal files ─────────────────────────────────────────────

for item in "${STRATUM_INTERNAL[@]}"; do
  rm -rf "${PROJECT_DIR:?}/$item"
done

echo ""
echo "Project '$PROJECT_DIR' created. Running setup..."
echo ""

# ── Run install.sh ────────────────────────────────────────────────────────────
# Use bash (not exec) so control returns here for post-install cleanup.
# Restore stdin from the terminal — curl pipe stole it.

cd "$PROJECT_DIR"
bash install.sh </dev/tty

# ── Post-install cleanup ──────────────────────────────────────────────────────
# .template/ is only needed during install.sh (storage overlay). Remove it now.

rm -rf .template

# ── Initialize fresh git history ─────────────────────────────────────────────
# Do this last so the single initial commit reflects the fully configured project.

rm -rf .git
git init -q
git add .
git commit -q -m "Initial commit from Stratum"

echo ""
echo "Done! Next: cd $PROJECT_DIR && docker compose up -d"
