# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Stack

Stratum is a backend boilerplate: **Hasura GraphQL Engine + NestJS + PostgreSQL**, optionally with **Garage S3** object storage. Everything runs in Docker Compose.

- Hasura (port 8080) — sole public-facing GraphQL API
- NestJS (port 3000) — internal business logic, never called by clients directly
- PostgreSQL (port 5432) — primary datastore, accessed only by Hasura
- Garage S3 (port 3902) — optional, S3-compatible object storage

## Development Commands

All NestJS commands run from `nestjs/`:

```bash
pnpm install          # install deps
pnpm run start:dev    # dev server with hot-reload
pnpm run build        # production build
pnpm run test         # unit tests (*.spec.ts in src/)
pnpm run test:e2e     # E2E tests
pnpm run test:cov     # coverage report
pnpm run lint         # ESLint with --fix
pnpm run format       # Prettier
pnpm run codegen      # generate TypeScript SDK from Hasura schema
```

Run a single test file:
```bash
pnpm run test -- --testPathPattern=storage.service
```

Start the full stack:
```bash
cp .env.example .env  # fill in secrets
docker compose up -d
docker compose logs -f nestjs  # tail logs
```

Hasura migrations (from `hasura/`):
```bash
hasura migrate apply --database-name default
hasura migrate apply --down 1 --database-name default  # rollback
hasura migrate status --database-name default
hasura metadata export   # after changing permissions in Console
hasura metadata apply    # sync metadata to running Hasura
```

## Architecture

**Key rule:** Clients speak to Hasura only. NestJS is an internal service — it only receives requests from Hasura (Actions, Event Triggers, Remote Schema) and never from clients.

### NestJS integration points with Hasura

- **Actions** — custom mutations/queries routed via `POST /actions/...`. Hasura calls NestJS synchronously and returns the result to the client.
- **Event Triggers** — async webhooks on INSERT/UPDATE/DELETE, routed via `POST /webhooks/...`. Validated with `HASURA_EVENT_SECRET` header using `HasuraWebhookGuard`.
- **Remote Schema** — additional GraphQL types from NestJS merged into Hasura's schema.

Use `HasuraService` (`nestjs/src/hasura/hasura.service.ts`) for all NestJS→Hasura GraphQL calls:

```typescript
const result = await this.hasura.query(`query { posts { id } }`);
const result = await this.hasura.mutate(mutation, variables);
```

### Permissions

Row-level data access and role-based mutation access are enforced in Hasura metadata (not in NestJS). NestJS guards are only for cross-service auth and rate limiting.

### Storage module

`StorageModule` (`nestjs/src/storage/`) is conditionally loaded based on the `STORAGE_ENABLED` env var. The upload flow: client requests a presigned URL via a Hasura Action → NestJS calls Garage → returns URL → client uploads directly to Garage. NestJS never proxies file bytes.

## Database Conventions

**All schema changes go through Hasura migrations.** Never modify the database directly.

Every standard table must have these 6 auditable fields:

| Field | Type |
|---|---|
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` |
| `created_by` | `UUID REFERENCES public.users(id)` |
| `updated_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` |
| `updated_by` | `UUID REFERENCES public.users(id)` |
| `deleted_at` | `TIMESTAMPTZ` (NULL = active) |
| `deleted_by` | `UUID REFERENCES public.users(id)` |

Exceptions (no audit fields needed): junction tables, lookup/enum tables, event log tables.

**Soft-delete only** — never hard-delete auditable records. Use `deleted_at`/`deleted_by` and filter all user-role selects with `{ "deleted_at": { "_is_null": true } }`.

Audit fields are set automatically — clients never send them:
- `created_by`, `updated_by`, `deleted_by` → Hasura Column Preset: `x-hasura-user-id`
- `updated_at` → Hasura Column Preset: `now()` on UPDATE
- `created_at` → PostgreSQL `DEFAULT NOW()`

## Task Management

- Write a plan to `tasks/todo.md` with checkable items before starting non-trivial work.
- After any correction, record the pattern in `tasks/lessons.md`.
- Review `tasks/lessons.md` at the start of each session.

## Workflow Orchestration

### 1. Plan Mode Default

- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately - don't keep pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### 2. Subagent Strategy

- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One tack per subagent for focused execution

### 3. Self-Improvement Loop

- After ANY correction from the user: update `tasks/lessons.md` with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review lessons at session start for relevant project

### 4. Verification Before Done

- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

### 5. Demand Elegance (Balanced)

- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes - don't over-engineer
- Challenge your own work before presenting it

### 6. Autonomous Bug Fixing

- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests - then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how

## Core Principles

- **Simplicity First**: Make every change as simple as possible. Impact minimal code.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
- **Minimal Impact**: Changes should only touch what's necessary. Avoid introducing bugs.
