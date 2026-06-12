# Local Development

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [Hasura CLI](https://hasura.io/docs/latest/hasura-cli/install-hasura-cli/) — required only for schema changes

```bash
# Install Hasura CLI (macOS)
brew install hasura-cli

# Or via curl
curl -L https://github.com/hasura/graphql-engine/raw/stable/cli/get.sh | bash
```

## Quick Start

```bash
# 1. Run the setup wizard (generates .env and docker-compose.yml)
./install.sh

# 2. Start the dev stack
make dev
```

That's it. The dev stack starts with hot reload enabled and all ports exposed.

## Services & Ports

| Service    | Port | Description                        |
|------------|------|------------------------------------|
| Hasura     | 8080 | GraphQL API + Console              |
| NestJS     | 3000 | Business logic (exposed in dev)    |
| PostgreSQL | 5432 | Database (exposed in dev)          |
| RustFS     | 9000 | S3 API (if storage enabled)        |
| RustFS UI  | 9001 | S3 Console (if storage enabled)    |

## Dev Stack Commands

```bash
make dev            # Start stack in dev mode
make dev-down       # Stop dev stack
make dev-logs       # Tail all logs
make dev-reset      # Wipe volumes and restart fresh
```

## NestJS Hot Reload

NestJS runs inside Docker with source code mounted from `./nestjs`. Any change to a file under `nestjs/src/` triggers an automatic restart — no rebuild needed.

```bash
# Watch NestJS logs
make dev-logs

# Or just NestJS:
docker compose -f docker-compose.yml -f docker-compose.dev.yml logs -f nestjs
```

Test the health endpoint:
```bash
curl localhost:3000/health
# {"status":"ok"}
```

## Database Access

PostgreSQL is exposed on `localhost:5432` in dev mode. Connect with any SQL client (TablePlus, DBeaver, psql):

- **Host**: `localhost`
- **Port**: `5432`
- **Database**: value of `POSTGRES_DB` in `.env` (default: `stratum`)
- **User/Password**: `POSTGRES_USER` / `POSTGRES_PASSWORD` from `.env`

## Hasura Schema Changes

> **Important**: Do not use the browser console directly for schema changes — those changes are saved to the database only and will be lost. Use `make hasura-console` instead, which routes changes through the Hasura CLI so they are written to `hasura/metadata/` and `hasura/migrations/`.

```bash
# Start the Hasura CLI console (proxied through CLI)
make hasura-console
# Opens http://localhost:9695 in your browser
```

After making changes in the console, commit the generated files:

```bash
git add hasura/metadata hasura/migrations
git commit -m "feat: add users table"
```

For more on migrations and metadata, see [adding-tables.md](./adding-tables.md).

## Difference from Production Mode

| Feature              | `make dev`          | `make up` / `docker compose up -d` |
|----------------------|---------------------|-------------------------------------|
| NestJS hot reload    | Yes (volume mount)  | No (compiled image)                 |
| PostgreSQL port      | Exposed (5432)      | Internal only                       |
| NestJS port          | Exposed (3000)      | Internal only                       |
| Hasura Console       | Enabled             | Disabled                            |
| Hasura Dev Mode      | Enabled             | Disabled                            |
| NestJS NODE_ENV      | `development`       | `production`                        |
