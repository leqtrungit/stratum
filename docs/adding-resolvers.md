# Adding Resolvers to Stratum

> This guide explains how to write custom business logic in NestJS — both GraphQL resolvers and REST endpoints.

---

## Overview

In Stratum, **Hasura handles auto-generated CRUD** for your database tables. NestJS is where you write **custom business logic** that goes beyond simple CRUD:

- Complex queries with transformation logic
- Side effects (sending emails, calling external APIs)
- Authentication-gated operations
- Webhook handlers for Hasura event triggers

---

## NestJS Module Structure

Every feature in NestJS is a **module**:

```
nestjs/src/<feature>/
├── <feature>.module.ts
├── <feature>.service.ts
├── <feature>.resolver.ts   # GraphQL
├── <feature>.controller.ts # REST
└── dto/
    └── create-<feature>.dto.ts
```

---

## Creating a New Module

```bash
cd nestjs/
pnpm run nest generate module <feature>
pnpm run nest generate service <feature>
pnpm run nest generate controller <feature>
```

Register in `app.module.ts`:

```typescript
import { FeatureModule } from './feature/feature.module';

@Module({
  imports: [FeatureModule],
})
export class AppModule {}
```

---

## Calling Hasura from a Service

Use the `HasuraService` to make internal GraphQL calls:

```typescript
@Injectable()
export class PostsService {
  constructor(private readonly hasura: HasuraService) {}

  async findAll() {
    const query = `query { posts { id title created_at } }`;
    const result = await this.hasura.query(query);
    return result.posts;
  }

  async create(data: { title: string; content: string }) {
    const mutation = `
      mutation CreatePost($title: String!, $content: String!) {
        insert_posts_one(object: { title: $title, content: $content }) {
          id title
        }
      }
    `;
    const result = await this.hasura.mutate(mutation, data);
    return result.insert_posts_one;
  }
}
```

---

## Writing a Hasura Event Trigger Handler

```typescript
@Controller('webhooks')
export class WebhooksController {
  @Post('on-user-created')
  async onUserCreated(@Body() event: HasuraEvent, @Headers('x-hasura-event-secret') secret: string) {
    if (secret !== process.env.HASURA_EVENT_SECRET) throw new UnauthorizedException();
    const newUser = event.event.data.new;
    await this.emailService.sendWelcome(newUser.email);
    return { success: true };
  }
}
```

Register in Hasura: **Events → Create Event Trigger → webhook URL: `http://nestjs:3000/webhooks/...`**

---

## Event Trigger Setup

Event Triggers let Hasura call NestJS automatically when rows are inserted, updated, or deleted.

### 1. Write the Handler

```typescript
@Controller('events')
@UseGuards(HasuraWebhookGuard)
export class UsersEventController {
  @Post('on-user-created')
  async onUserCreated(@Body() event: any) {
    const newUser = event.event.data.new;
    await this.emailService.sendWelcome(newUser.email);
    return { success: true };
  }
}
```

### 2. Register the Trigger in Hasura

**Via Console:**

1. Go to **Events → Event Triggers → Create**
2. **Trigger name:** `on_user_created`
3. **Table:** `public.users`
4. **Operations:** `INSERT`
5. **Webhook URL:** `http://nestjs:3000/events/on-user-created`
6. **Headers:** add `x-hasura-event-secret: {{HASURA_EVENT_SECRET}}`

**Via Metadata YAML** (`hasura/metadata/databases/default/tables/public_users.yaml`):

```yaml
event_triggers:
  - name: on_user_created
    definition:
      enable_manual: false
      insert:
        columns: "*"
    webhook: "{{NESTJS_WEBHOOK_URL}}/events/on-user-created"
    headers:
      - name: x-hasura-event-secret
        value_from_env: HASURA_EVENT_SECRET
    retry_conf:
      num_retries: 3
      interval_sec: 10
      timeout_sec: 60
```

### 3. Debug Failed Events

In the Hasura Console: **Events → <trigger name> → Pending / Processed Events** shows each invocation, status, request body, and response. Re-deliver failed events manually from here.

---

## Testing Actions Locally

### From Hasura Console GraphiQL

1. Open `http://localhost:8080/console` → **API → GraphiQL**
2. Set headers:
   ```
   x-hasura-role: user
   x-hasura-user-id: <your-user-uuid>
   ```
3. Run the mutation:
   ```graphql
   mutation {
     requestUploadUrl(filename: "test.png", mimeType: "image/png") {
       uploadUrl
       fileKey
     }
   }
   ```

### Direct HTTP (bypass Hasura for unit testing the handler)

```bash
curl -X POST http://localhost:3000/actions/request-upload-url \
  -H "Content-Type: application/json" \
  -H "x-hasura-event-secret: changeme-event-secret" \
  -d '{
    "input": { "filename": "test.png", "mimeType": "image/png" },
    "session_variables": { "x-hasura-user-id": "some-uuid", "x-hasura-role": "user" }
  }'
```

### Debugging Tips

- **NestJS logs:** `docker compose logs -f nestjs`
- **Hasura Action logs:** Console → **Events → one-off scheduled events** (for synchronous actions, check NestJS logs directly)
- **400 / 500 from NestJS:** Hasura surfaces the error body back to the GraphQL client — check `errors[0].extensions.internal`

---

## HasuraWebhookGuard Scope

`HasuraWebhookGuard` validates the `x-hasura-event-secret` header on every request. Apply it to **all** NestJS controllers that Hasura calls:

| Controller | Guard needed? | Reason |
|---|---|---|
| `@Controller('actions')` | **Yes** — always | Hasura Action handlers must not be callable without the shared secret |
| `@Controller('events')` | **Yes** — always | Event Trigger handlers fire on DB changes; must be authenticated |
| `@Controller('remote-schema')` | **Yes** — always | Remote Schema resolvers are internal |
| Login / public endpoints | **No** | These are unauthenticated by design — do not put them in a guarded controller |

**Implementation:**

```typescript
// Apply at controller level to guard all routes in the class
@Controller('actions')
@UseGuards(HasuraWebhookGuard)
export class MyActionController { ... }

// Or apply at individual route level for mixed controllers
@Post('public-health')
healthCheck() { ... }          // no guard

@Post('my-action')
@UseGuards(HasuraWebhookGuard)
myAction(@Body() body: any) { ... }
```

---

## Hasura Permissions vs NestJS Guards

| Use case | Where to enforce |
|---|---|
| Row-level data access | Hasura permissions (JWT claims) |
| Role-based mutation access | Hasura permissions |
| Hasura → NestJS request authentication | `HasuraWebhookGuard` (shared secret) |
| Rate limiting, feature flags | NestJS guard / interceptor |
| Complex cross-service auth | NestJS guard |

---

*See also: [Architecture](./architecture.md) · [Adding Tables](./adding-tables.md) · [Adding Feature](./adding-feature.md) · [Authentication](./authentication.md) · [Storage Usage](./storage-usage.md)*
