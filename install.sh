#!/bin/bash

# =============================================================================
# Stratum — Interactive Setup Script
# =============================================================================

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=============================================================================${NC}"
echo -e "${BLUE}  Stratum — Backend Boilerplate Setup${NC}"
echo -e "${BLUE}=============================================================================${NC}"

# 1. Project Name
read -p "Enter project name [stratum]: " PROJECT_NAME
PROJECT_NAME=${PROJECT_NAME:-stratum}

# 2. Enable Storage
read -p "Enable RustFS S3 Object Storage? (y/n) [n]: " ENABLE_STORAGE
ENABLE_STORAGE=${ENABLE_STORAGE:-n}

# 3. Generate Secrets
echo -e "${YELLOW}Generating random secrets...${NC}"
ADMIN_SECRET=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 32 | head -n 1)
JWT_SECRET=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 32 | head -n 1)
EVENT_SECRET=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 32 | head -n 1)
DB_PASSWORD=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 16 | head -n 1)
STORAGE_ACCESS_KEY=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 20 | head -n 1)
STORAGE_SECRET_KEY=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 40 | head -n 1)

# 4. Create .env
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
    
    # 5. Generate docker-compose.yml (Merged)
    echo -e "${YELLOW}Generating merged docker-compose.yml with storage...${NC}"
    # Use docker compose config to merge files properly
    # We pass the newly created .env to ensure required variables are present
    docker compose --env-file .env -f docker-compose.base.yml -f docker-compose.storage.yml config > docker-compose.yml
else
    cp docker-compose.base.yml docker-compose.yml
    
    # Clean up Storage-related metadata and migrations
    echo -e "${YELLOW}Cleaning up Storage-related metadata and migrations...${NC}"
    
    # Use sed to delete lines between markers (inclusive)
    # This works on most Unix systems including macOS
    sed -i.bak '/# STORAGE_START/,/# STORAGE_END/d' hasura/metadata/actions.yaml
    sed -i.bak '/# STORAGE_START/,/# STORAGE_END/d' hasura/metadata/custom_types.yaml
    sed -i.bak '/# STORAGE_START/,/# STORAGE_END/d' hasura/metadata/databases/default/tables/tables.yaml
    
    # Delete storage migration and table metadata
    rm -rf hasura/migrations/default/*_files_table
    rm -f hasura/metadata/databases/default/tables/public_files.yaml
fi

# Clean up .bak files from sed
find . -name "*.bak" -delete

echo -e "${GREEN}=============================================================================${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${GREEN}=============================================================================${NC}"
echo -e ""
echo -e "Next steps:"
echo -e "  1. Run: ${YELLOW}docker compose up -d${NC}"
echo -e "  2. Access Hasura: ${YELLOW}http://localhost:8080${NC}"
if [[ "$ENABLE_STORAGE" == "y" || "$ENABLE_STORAGE" == "Y" ]]; then
echo -e "  3. Access RustFS Console: ${YELLOW}http://localhost:9001${NC}"
fi
echo -e ""
