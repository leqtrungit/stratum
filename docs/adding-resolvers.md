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

## Hasura Permissions vs NestJS Guards

| Use case | Where to enforce |
|---|---|
| Row-level data access | Hasura permissions (JWT claims) |
| Role-based mutation access | Hasura permissions |
| Rate limiting, feature flags | NestJS guard / interceptor |
| Complex cross-service auth | NestJS guard |

---

*See also: [Architecture](./architecture.md) · [Adding Tables](./adding-tables.md) · [Storage Usage](./storage-usage.md)*
