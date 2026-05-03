# Stratum — Test Use Cases

> This document tracks all automated test use cases for Stratum. It is maintained by AI agents and updated whenever the system architecture or features change.

## 1. Setup & Installation (CLI Level)
- **Case 1.1: Core Only Setup**
  - Run `./install.sh` with `STORAGE_ENABLED=n`.
  - **Verify**: `.env` is created, `docker-compose.yml` excludes Garage, Hasura metadata is cleaned (no storage actions).
- **Case 1.2: Full Stack Setup**
  - Run `./install.sh` with `STORAGE_ENABLED=y`.
  - **Verify**: `docker-compose.yml` includes all services, metadata is complete.
- **Case 1.3: Secret Generation**
  - **Verify**: Secrets like `ADMIN_SECRET` and `JWT_SECRET` are unique and random on each run.

## 2. Infrastructure & Connectivity
- **Case 2.1: Service Health**
  - **Verify**: Hasura `/healthz` returns 200.
  - **Verify**: NestJS `/health` returns status 'ok'.
  - **Verify**: Docker containers (Postgres, Garage) are healthy.
- **Case 2.2: Internal Networking**
  - **Verify**: Hasura can reach NestJS webhook endpoints.
  - **Verify**: NestJS can reach Hasura GraphQL API via admin secret.
  - **Verify**: NestJS can connect to Garage S3 API.

## 3. Core API & Database
- **Case 3.1: Users Table**
  - **Verify**: Minimal `users` table exists and supports basic CRUD.
- **Case 3.2: Audit Fields & Triggers**
  - **Verify**: `updated_at` is auto-updated on record change via Postgres trigger.
  - **Verify**: `created_by` is auto-set by Hasura Column Presets from JWT/Session.
- **Case 3.3: Permissions**
  - **Verify**: Row-level security prevents User A from reading User B's data.

## 4. Module: Storage (Full Flow)
- **Case 4.1: Upload Pipeline**
  1. `requestUploadUrl` Action -> Get presigned URL.
  2. PUT file to S3 -> 200 OK.
  3. `confirmUpload` Action -> Metadata saved in `files` table.
- **Case 4.2: Delete Flow**
  - `deleteFile` Action -> Object removed from S3, DB record soft-deleted (`deleted_at` set).
- **Case 4.3: Security**
  - **Verify**: User A cannot confirm or delete User B's files.

## 5. Security & Webhooks
- **Case 5.1: Webhook Secret Validation**
  - **Verify**: NestJS rejects Action calls with missing or invalid `x-hasura-event-secret`.
- **Case 5.2: GraphQL Codegen**
  - **Verify**: `pnpm codegen` generates typed SDK matching current schema.
