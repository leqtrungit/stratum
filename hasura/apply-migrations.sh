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

# Apply migrations
echo "Applying migrations..."
hasura migrate apply --database-name default --endpoint "$HASURA_ENDPOINT" --admin-secret "$ADMIN_SECRET" --project /hasura

# Apply metadata
echo "Applying metadata..."
hasura metadata apply --endpoint "$HASURA_ENDPOINT" --admin-secret "$ADMIN_SECRET" --project /hasura

# Apply seeds only for development
if [ "$ENVIRONMENT" = "dev" ]; then
    echo "Applying seeds (development only)..."
    hasura seeds apply --database-name default --endpoint "$HASURA_ENDPOINT" --admin-secret "$ADMIN_SECRET" --project /hasura
else
    echo "Skipping seeds for production environment"
fi

echo "Hasura setup completed for $ENVIRONMENT environment!"
