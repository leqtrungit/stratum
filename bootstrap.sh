#!/bin/bash

# =============================================================================
# Stratum — Clean Boilerplate Bootstrapper
# =============================================================================
# This script initializes a fresh Stratum project without cloning the source repo.
# =============================================================================

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 1. Configuration
REPO_URL="https://github.com/leqtrungit/stratum" # Replace with your actual repo URL
BRANCH="main"
TMP_DIR="/tmp/stratum-bootstrap-$(date +%s)"

# 2. Welcome Message
echo -e "${BLUE}=============================================================================${NC}"
echo -e "${BLUE}  🚀 Stratum — Backend Boilerplate Generator${NC}"
echo -e "${BLUE}=============================================================================${NC}"

# 3. Prerequisites Check
if ! command -v tar &> /dev/null || ! command -v curl &> /dev/null; then
    echo -e "${RED}Error: tar and curl are required.${NC}"
    exit 1
fi

# 4. User Inputs
read -p "Enter your project name [my-stratum-app]: " PROJECT_NAME
PROJECT_NAME=${PROJECT_NAME:-my-stratum-app}

# Validate project name (lowercase, no spaces)
PROJECT_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g')

read -p "Enable S3 Object Storage (RustFS)? (y/n) [n]: " ENABLE_STORAGE
ENABLE_STORAGE=${ENABLE_STORAGE:-n}

# 5. Download and Extract
echo -e "${YELLOW}Downloading boilerplate template...${NC}"
mkdir -p "$TMP_DIR"

# Download tarball of the repo (lighter than git clone)
# Note: Adjust URL pattern based on GitHub/GitLab
TARBALL_URL="${REPO_URL}/archive/refs/heads/${BRANCH}.tar.gz"

curl -sSL "$TARBALL_URL" -o "$TMP_DIR/template.tar.gz"

echo -e "${YELLOW}Extracting core components...${NC}"
mkdir -p "$TMP_DIR/extracted"
tar -xzf "$TMP_DIR/template.tar.gz" -C "$TMP_DIR/extracted" --strip-components=1

# 6. Selectively Copy Files (The "Clean" Part)
echo -e "${YELLOW}Initializing clean project structure in: $(pwd)${NC}"

# Define what to include in the final project
CORE_FOLDERS=("nestjs" "hasura")
CORE_FILES=("docker-compose.base.yml" "docker-compose.storage.yml" ".env.example" "Makefile" "README.md")

for folder in "${CORE_FOLDERS[@]}"; do
    if [ -d "$TMP_DIR/extracted/$folder" ]; then
        cp -R "$TMP_DIR/extracted/$folder" ./
    fi
done

for file in "${CORE_FILES[@]}"; do
    if [ -f "$TMP_DIR/extracted/$file" ]; then
        cp "$TMP_DIR/extracted/$file" ./
    fi
done

# 7. Project Customization Logic (formerly install.sh)
echo -e "${YELLOW}Customizing project secrets and configuration...${NC}"

# Generate Secrets
ADMIN_SECRET=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 32 | head -n 1)
JWT_SECRET=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 32 | head -n 1)
EVENT_SECRET=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 32 | head -n 1)
DB_PASSWORD=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 16 | head -n 1)
STORAGE_ACCESS_KEY=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 20 | head -n 1)
STORAGE_SECRET_KEY=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 40 | head -n 1)

# Create .env
cp .env.example .env

# Replace placeholders
# We use | as delimiter to avoid issues with special chars
sed -i.bak "s|^PROJECT_NAME=.*|PROJECT_NAME=$PROJECT_NAME|" .env
sed -i.bak "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$DB_PASSWORD|" .env
sed -i.bak "s|^DATABASE_URL=.*|DATABASE_URL=postgres://stratum:$DB_PASSWORD@postgres:5432/stratum|" .env
sed -i.bak "s|^HASURA_GRAPHQL_DATABASE_URL=.*|HASURA_GRAPHQL_DATABASE_URL=postgres://stratum:$DB_PASSWORD@postgres:5432/stratum|" .env
sed -i.bak "s|^HASURA_GRAPHQL_ADMIN_SECRET=.*|HASURA_GRAPHQL_ADMIN_SECRET=$ADMIN_SECRET|" .env
sed -i.bak "s|^HASURA_GRAPHQL_JWT_SECRET=.*|HASURA_GRAPHQL_JWT_SECRET={\"type\":\"HS256\",\"key\":\"$JWT_SECRET\"}|" .env
sed -i.bak "s|^HASURA_ADMIN_SECRET=.*|HASURA_ADMIN_SECRET=$ADMIN_SECRET|" .env
sed -i.bak "s|^HASURA_EVENT_SECRET=.*|HASURA_EVENT_SECRET=$EVENT_SECRET|" .env

if [[ "$ENABLE_STORAGE" == "y" || "$ENABLE_STORAGE" == "Y" ]]; then
    sed -i.bak "s|^STORAGE_ENABLED=.*|STORAGE_ENABLED=true|" .env
    sed -i.bak "s|^S3_ACCESS_KEY=.*|S3_ACCESS_KEY=$STORAGE_ACCESS_KEY|" .env
    sed -i.bak "s|^S3_SECRET_KEY=.*|S3_SECRET_KEY=$STORAGE_SECRET_KEY|" .env
    
    # Merge docker-compose
    if command -v docker &> /dev/null; then
        docker compose --env-file .env -f docker-compose.base.yml -f docker-compose.storage.yml config > docker-compose.yml
    else
        echo -e "${YELLOW}Warning: Docker not found. Manual merge required.${NC}"
        cat docker-compose.base.yml docker-compose.storage.yml > docker-compose.yml
    fi
else
    cp docker-compose.base.yml docker-compose.yml
    
    # Cleanup Storage metadata from Hasura
    echo -e "${YELLOW}Removing storage-related components...${NC}"
    
    # 1. Clean Hasura Metadata
    sed -i.bak '/STORAGE_START/,/STORAGE_END/d' hasura/metadata/actions.yaml || true
    sed -i.bak '/STORAGE_START/,/STORAGE_END/d' hasura/metadata/databases/default/tables/tables.yaml || true
    rm -rf hasura/migrations/default/*_files_table || true
    rm -f hasura/metadata/databases/default/tables/public_files.yaml || true

    # 2. Clean NestJS Code
    sed -i.bak '/STORAGE_START/,/STORAGE_END/d' nestjs/src/app.module.ts || true
    rm -rf nestjs/src/storage || true
fi

# Cleanup all markers (even if storage is enabled, we remove the comments)
echo -e "${YELLOW}Finalizing files...${NC}"
grep -rl "STORAGE_START" . --exclude="bootstrap.sh" | xargs sed -i.bak '/STORAGE_START/d' || true
grep -rl "STORAGE_END" . --exclude="bootstrap.sh" | xargs sed -i.bak '/STORAGE_END/d' || true


# 8. Cleanup and Finalize
rm -rf "$TMP_DIR"
find . -name "*.bak" -delete
rm -f docker-compose.base.yml docker-compose.storage.yml # Clean up source fragments


# Initialize fresh git
if command -v git &> /dev/null; then
    git init -q
    echo -e "${YELLOW}Initialized fresh Git repository.${NC}"
fi

echo -e "${GREEN}=============================================================================${NC}"
echo -e "${GREEN}  ✨ Project Setup Complete!${NC}"
echo -e "${GREEN}=============================================================================${NC}"
echo -e ""
echo -e "Project Location: $(pwd)"
echo -e "Project Name:     ${BLUE}$PROJECT_NAME${NC}"
echo -e ""
echo -e "Next steps:"
echo -e "  1. ${YELLOW}docker compose up -d${NC}"
echo -e "  2. Start developing your Tables and Actions!"
echo -e ""
