# Stratum — Implementation Todo

## Confirmed Decisions
- `users` table: minimal seed (id + email only, no audit FKs on itself)
- Hasura: v2 latest CE
- install.sh v0.1: 2 questions (project name + enable storage?)
- NestJS package manager: pnpm

---

## v0.1 — Proof of Concept

### 1. Repo Skeleton
- [x] Create `tasks/` directory (this file)
- [x] Create `.gitignore`
- [x] Create `.env.example` with all required variables

### 2. Docker Compose
- [x] Create `docker-compose.base.yml` (Postgres 16 + Hasura v2 + NestJS)
- [x] Create `docker-compose.storage.yml` (Garage + WebUI overlay)

### 3. NestJS Application
- [x] Init NestJS project in `nestjs/` using pnpm
- [x] Create `nestjs/Dockerfile` (multi-stage build)
- [x] Implement `HasuraModule` + `HasuraService` (internal GraphQL client with admin secret)
- [x] Implement `HasuraWebhookGuard` (validate `x-hasura-event-secret` header)
- [x] Implement `StorageModule` + `StorageService` (S3 SDK wrapper for Garage)
- [x] Implement `StorageAction` controller (requestUploadUrl, confirmUpload, deleteFile handlers)
- [x] Wire up `AppModule` with conditional `StorageModule` import via `STORAGE_ENABLED` env

### 4. Hasura
- [x] Create `hasura/config.yaml`
- [x] Create initial migration: `users` table (minimal: id, email, created_at)
- [x] Create migration: `files` table (full audit fields, references users)
- [x] Create Hasura metadata: track tables, relationships
- [x] Define Hasura Actions: `requestUploadUrl`, `confirmUpload`, `deleteFile`
- [x] Set row-level permissions on `files` table (user role)

### 5. Install Script
- [x] Create `install.sh` (bash)
  - [x] Question 1: Project name
  - [x] Question 2: Enable Garage S3 storage? (y/n)
  - [x] Generate `.env` from `.env.example` with filled values + random secrets

  - [x] Generate `docker-compose.yml` by merging base + storage (if selected)

### 6. Verification
- [ ] `docker compose up -d` → all services healthy
- [x] Hasura healthz returns 200
- [x] NestJS container starts without errors (Fixed MODULE_NOT_FOUND error by excluding codegen.ts from build)
- [ ] `requestUploadUrl` Action returns a presigned URL
- [ ] Full upload flow: requestUploadUrl → PUT Garage → confirmUpload → record in `files` table

---

## v0.2 — Developer Ready

- [ ] Extend `install.sh` to 4–6 questions with input validation
- [ ] Add `Makefile` (up, down, reset, console, logs targets)
- [ ] `AppModule` cleanly toggles `StorageModule` via env without code change
- [ ] Create `docs/contributing.md`
- [ ] README final polish

---

## v0.3 — Production Hardened

- [ ] Add `nestjs/src/health/` with `/health` and `/ready` endpoints
- [ ] Add `healthcheck` directives to all Docker Compose services
- [ ] Add `deploy.resources.limits` to Docker Compose services
- [ ] Create `.github/workflows/ci.yml` (build NestJS, run Hasura migrations, lint)
- [ ] Hasura connection pooling config

---

## Automated Testing Implementation (docs/test-use-cases.md)

### 1. Setup & Installation (CLI Level)
- [ ] Create `tests/system` directory with testing infrastructure
- [ ] Implement Case 1.1: Core Only Setup (run install.sh, verify files)
- [ ] Implement Case 1.2: Full Stack Setup (run install.sh, verify files)
- [ ] Implement Case 1.3: Secret Generation (verify uniqueness)

### 2. Infrastructure & Connectivity
- [ ] Implement Case 2.1: Service Health (Hasura, NestJS, Postgres, Garage)
- [ ] Implement Case 2.2: Internal Networking (Hasura -> NestJS, NestJS -> Hasura, NestJS -> Garage)

---

## Review

### 2026-05-03: Fixed NestJS MODULE_NOT_FOUND error
- **Issue**: NestJS container failed to start because `dist/main.js` was missing.
- **Cause**: `codegen.ts` in the root was being compiled, causing `tsc` to create a `dist/src` subfolder.
- **Fix**: Excluded `codegen.ts` from `tsconfig.build.json`.
- **Status**: Verified. Container is Up and Healthy.
