#!/bin/bash

# =============================================================================
# Stratum — Interactive Setup Script
# =============================================================================

set -e

# Safety guard: must run from a directory that has the required project files
if [[ ! -f ".env.example" || ! -d "hasura" || ! -f "docker-compose.base.yml" ]]; then
  echo "Error: run install.sh from the project root (must contain .env.example, hasura/, docker-compose.base.yml)" >&2
  exit 1
fi

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=============================================================================${NC}"
echo -e "${BLUE}  Stratum — Backend Boilerplate Setup${NC}"
echo -e "${BLUE}=============================================================================${NC}"

# 1. Project Name
_NI=${STRATUM_PROJECT_NAME:+1}
if [ -n "${STRATUM_PROJECT_NAME:-}" ]; then
  PROJECT_NAME=$(echo "$STRATUM_PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g' | sed 's/[^a-z0-9-]//g')
else
  while true; do
    read -p "Enter project name [stratum]: " PROJECT_NAME
    PROJECT_NAME=${PROJECT_NAME:-stratum}
    # Normalize: lowercase, spaces → hyphens, strip non-alphanumeric except hyphens
    PROJECT_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g' | sed 's/[^a-z0-9-]//g')
    if [[ -z "$PROJECT_NAME" ]]; then
      echo -e "${RED}Project name cannot be empty or contain only special characters.${NC}"
    elif [[ ! "$PROJECT_NAME" =~ ^[a-z] ]]; then
      echo -e "${RED}Project name must start with a lowercase letter.${NC}"
    else
      break
    fi
  done
fi

# 2. Enable Storage
if [ -n "${STRATUM_STORAGE:-}" ]; then
  ENABLE_STORAGE="$STRATUM_STORAGE"
else
  while true; do
    read -p "Enable RustFS S3 Object Storage? (y/n) [n]: " ENABLE_STORAGE
    ENABLE_STORAGE=${ENABLE_STORAGE:-n}
    case "$ENABLE_STORAGE" in
      y|Y|n|N) break ;;
      *) echo -e "${RED}Please enter y or n.${NC}" ;;
    esac
  done
fi

# 3. Confirm
echo ""
echo -e "${BLUE}Summary:${NC}"
echo -e "  Project name : ${YELLOW}$PROJECT_NAME${NC}"
echo -e "  Storage      : ${YELLOW}$([[ "$ENABLE_STORAGE" =~ ^[yY]$ ]] && echo enabled || echo disabled)${NC}"
echo ""
if [ -z "${_NI:-}" ]; then
  read -p "Proceed with setup? (y/n) [y]: " CONFIRM
  CONFIRM=${CONFIRM:-y}
  if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

# 4. Generate Secrets
echo -e "${YELLOW}Generating random secrets...${NC}"
ADMIN_SECRET=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 32)
JWT_SECRET=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 32)
EVENT_SECRET=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 32)
DB_PASSWORD=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 16)
STORAGE_ACCESS_KEY=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 20)
STORAGE_SECRET_KEY=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 40)

# 5. Create .env
echo -e "${YELLOW}Creating .env file...${NC}"
cp .env.example .env

# Replace placeholders in .env
# Using a different delimiter for sed because of potential special characters in secrets
sed -i.bak "s/^PROJECT_NAME=.*/PROJECT_NAME=$PROJECT_NAME/" .env
sed -i.bak "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$DB_PASSWORD/" .env
sed -i.bak "s|^DATABASE_URL=.*|DATABASE_URL=postgres://stratum:$DB_PASSWORD@postgres:5432/stratum|" .env
sed -i.bak "s|^HASURA_GRAPHQL_DATABASE_URL=.*|HASURA_GRAPHQL_DATABASE_URL=postgres://stratum:$DB_PASSWORD@postgres:5432/stratum|" .env
sed -i.bak "s/^HASURA_GRAPHQL_ADMIN_SECRET=.*/HASURA_GRAPHQL_ADMIN_SECRET=$ADMIN_SECRET/" .env
sed -i.bak "s|^HASURA_GRAPHQL_JWT_SECRET=.*|HASURA_GRAPHQL_JWT_SECRET={\"type\":\"HS256\",\"key\":\"$JWT_SECRET\"}|" .env
sed -i.bak "s/^HASURA_ADMIN_SECRET=.*/HASURA_ADMIN_SECRET=$ADMIN_SECRET/" .env
sed -i.bak "s/^HASURA_EVENT_SECRET=.*/HASURA_EVENT_SECRET=$EVENT_SECRET/" .env

if [[ "$ENABLE_STORAGE" == "y" || "$ENABLE_STORAGE" == "Y" ]]; then
    sed -i.bak "s/^STORAGE_ENABLED=.*/STORAGE_ENABLED=true/" .env
    sed -i.bak "s/^S3_ACCESS_KEY=.*/S3_ACCESS_KEY=$STORAGE_ACCESS_KEY/" .env
    sed -i.bak "s/^S3_SECRET_KEY=.*/S3_SECRET_KEY=$STORAGE_SECRET_KEY/" .env
    
    # 6. Apply Storage template overlay (app.module.ts, metadata, etc.)
    echo -e "${YELLOW}Applying Storage Module overlay...${NC}"
    if [[ -d ".template/storage" ]]; then
      cp -R .template/storage/* ./
    else
      echo -e "${YELLOW}Warning: .template/storage not found — skipping overlay.${NC}"
    fi

    # 7. Generate docker-compose.yml (Merged)
    echo -e "${YELLOW}Generating merged docker-compose.yml with storage...${NC}"
    if ! docker info >/dev/null 2>&1; then
      echo -e "${RED}Error: Docker daemon is not running. Please start Docker and re-run install.sh.${NC}" >&2
      exit 1
    fi
    docker compose --env-file .env -f docker-compose.base.yml -f docker-compose.storage.yml config > docker-compose.yml
else
    cp docker-compose.base.yml docker-compose.yml
    
    # Clean up Storage-related metadata and migrations
    echo -e "${YELLOW}Cleaning up Storage-related metadata and migrations...${NC}"
    
    # Use sed to delete lines between markers (inclusive)
    # This works on most Unix systems including macOS
    for meta_file in \
        hasura/metadata/actions.yaml \
        hasura/metadata/actions.graphql \
        hasura/metadata/custom_types.yaml \
        hasura/metadata/databases/default/tables/tables.yaml; do
      if [[ -f "$meta_file" ]]; then
        sed -i.bak '/# STORAGE_START/,/# STORAGE_END/d' "$meta_file"
      fi
    done

    # Delete storage migration and table metadata
    rm -rf hasura/migrations/default/*_files_table
    rm -f hasura/metadata/databases/default/tables/public_files.yaml
fi

# Write hasura/.env for local Hasura CLI usage (make hasura-console)
echo "HASURA_GRAPHQL_ADMIN_SECRET=$ADMIN_SECRET" > hasura/.env

# Clean up .bak files from sed
find . -name "*.bak" -delete

echo -e "${GREEN}=============================================================================${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${GREEN}=============================================================================${NC}"
echo -e ""
echo -e "Next steps:"
echo -e "  1. Run: ${YELLOW}make dev${NC}               (local dev with hot reload)"
echo -e "     Or:  ${YELLOW}docker compose up -d${NC}   (production mode)"
echo -e "  2. Access Hasura: ${YELLOW}http://localhost:8080${NC}"
echo -e "  3. Schema changes: ${YELLOW}make hasura-console${NC} (tracks changes to files)"
if [[ "$ENABLE_STORAGE" == "y" || "$ENABLE_STORAGE" == "Y" ]]; then
echo -e "  4. Access RustFS Console: ${YELLOW}http://localhost:9001${NC}"
fi
echo -e ""
