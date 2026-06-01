---
name: nestjs
description: Guide for NestJS development in Stratum — modules, actions, event handlers, guards, and conventions
tags: [nestjs, typescript, graphql, actions, event-triggers, storage]
---

# NestJS Agent — Stratum Context

## Role

You own the `nestjs/` directory. You implement business logic that Hasura delegates to NestJS via **Actions** and **Event Triggers**. Clients NEVER call NestJS directly — only Hasura does.

## Architecture Rule

```
CLIENT → Hasura (GraphQL) → NestJS (internal webhook)
```

NestJS is NOT a public API. It is an internal webhook server. Never add public-facing routes. Never expose new ports.

## Project Structure

```
nestjs/src/
├── app.module.ts           # Root module — import new modules here
├── app.controller.ts       # GET /health only
├── main.ts
├── common/
│   └── guards/
│       └── hasura-webhook.guard.ts   # ALWAYS apply to action/event controllers
├── hasura/
│   ├── hasura.module.ts
│   └── hasura.service.ts    # Use for internal Hasura queries/mutations
└── storage/                 # Optional module (STORAGE_ENABLED env flag)
    ├── storage.module.ts
    ├── storage.service.ts
    └── storage.action.ts
```

## Conventions

### Creating a New Action

1. Create `src/<feature>/<feature>.action.ts`
2. Controller path: `@Controller('actions')` + `@Post('<action-name>')`
3. Always apply `@UseGuards(HasuraWebhookGuard)` — never skip
4. Read `session_variables` for user context (e.g. `x-hasura-user-id`)
5. Register the module in `app.module.ts`

```typescript
@Controller('actions')
@UseGuards(HasuraWebhookGuard)
export class MyAction {
  @Post('my-action')
  async handle(@Body() body: any) {
    const { input, session_variables } = body;
    // ...
  }
}
```

### Creating a New Event Handler

1. Create `src/<feature>/<feature>.event.ts`
2. Controller path: `@Controller('events')` + `@Post('<event-name>')`
3. Always apply `@UseGuards(HasuraWebhookGuard)`

### Calling Hasura Internally

Use `HasuraService` — never make raw HTTP calls to Hasura:

```typescript
constructor(private readonly hasura: HasuraService) {}

// Query
const result = await this.hasura.query(gql, variables);

// Mutation
const result = await this.hasura.mutate(gql, variables);
```

### Config & Env Variables

Use `configService.getOrThrow<string>('VAR_NAME')` for required vars — never optional access for mandatory config.

### ESM Imports

NestJS 11 with `nodenext` — local imports MUST have `.js` extension:

```typescript
// ✅ correct
import { HasuraService } from '../hasura/hasura.service.js';

// ❌ wrong
import { HasuraService } from '../hasura/hasura.service';
```

## What NOT to Touch

- `common/guards/hasura-webhook.guard.ts` — do not modify unless security change is explicitly requested
- `hasura/hasura.service.ts` — extend only, never break existing interface
- `app.controller.ts` GET /health — leave as-is
- Docker port mappings — NestJS port 3000 is intentionally NOT exposed to host

## Verification

After any change:

```bash
make test-smoke   # verify /health + container healthy
```

For NestJS-specific build check:
```bash
cd nestjs && pnpm build
```

## Hasura Side

When you add a new Action or Event Handler in NestJS, the corresponding Hasura metadata **must also be updated**:
- New action → update `hasura/metadata/actions.yaml` + `hasura/metadata/actions.graphql`
- New event trigger → update `hasura/metadata/databases/default/tables/public_<table>.yaml`

**Coordinate with the Hasura agent or update metadata yourself** — the stack won't work if NestJS and Hasura are out of sync.
