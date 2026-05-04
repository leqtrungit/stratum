#!/bin/bash

# Hasura Setup Script
# Usage: ./apply-migrations.sh [dev|prod]

set -e

ENVIRONMENT=${1:-dev}
HASURA_ENDPOINT="http://hasura:8080"
ADMIN_SECRET="${HASURA_GRAPHQL_ADMIN_SECRET:-myadminsecretkey}"

echo "Setting up Hasura for $ENVIRONMENT environment..."

# Wait for Hasura to be ready
echo "Waiting for Hasura to be ready..."
until curl -s "$HASURA_ENDPOINT/healthz" > /dev/null; do
    echo "Waiting for Hasura..."
    sleep 2
done

echo "Hasura is ready!"


# Apply metadata
echo "Applying metadata..."
hasura-cli metadata apply --endpoint "$HASURA_ENDPOINT" --admin-secret "$ADMIN_SECRET" --project /hasura

# Apply migrations
echo "Applying migrations..."
hasura-cli migrate apply --database-name default --endpoint "$HASURA_ENDPOINT" --admin-secret "$ADMIN_SECRET" --project /hasura

# Apply seeds only for development
if [ "$ENVIRONMENT" = "dev" ]; then
    echo "Checking for seeds (development only)..."
    if [ -d "/hasura/seeds/default" ] && [ "$(ls -A /hasura/seeds/default/*.sql 2>/dev/null)" ]; then
        echo "Applying seeds..."
        hasura-cli seeds apply --database-name default --endpoint "$HASURA_ENDPOINT" --admin-secret "$ADMIN_SECRET" --project /hasura
    else
        echo "No seeds found in /hasura/seeds/default, skipping."
    fi
else
    echo "Skipping seeds for production environment"
fi

echo "Hasura setup completed for $ENVIRONMENT environment!"
