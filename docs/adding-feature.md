# Adding a Feature End-to-End

> This guide walks through every layer you need to touch when adding a new feature to Stratum — from database migration to Hasura permissions to NestJS handler to testing.

---

## Overview

A complete feature in Stratum touches these layers, in order:

1. **Migration** — create the table(s) in PostgreSQL
2. **Hasura metadata** — track the table, define relationships and permissions
3. **NestJS handler** — write any custom business logic that Hasura can't do alone
4. **Hasura Action** (if NestJS is involved) — register the handler as a GraphQL mutation/query
5. **Tests** — verify the feature works end-to-end

---

## 1. Create the Migration

```bash
cd hasura/
hasura migrate create "create_posts_table" --database-name default
```

This creates two files under `migrations/default/<timestamp>_create_posts_table/`:

- `up.sql` — applies the change
- `down.sql` — rolls it back

**`up.sql` example:**

```sql
CREATE TABLE public.posts (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title       TEXT NOT NULL,
  body        TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by  UUID REFERENCES public.users(id),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_by  UUID REFERENCES public.users(id),
  deleted_at  TIMESTAMPTZ,
  deleted_by  UUID REFERENCES public.users(id)
);
```

**`down.sql` example:**

```sql
DROP TABLE IF EXISTS public.posts;
```

> Always include all [auditable fields](./adding-tables.md#auditable-fields-convention) unless your table is a junction, lookup, or log table.

Apply the migration:

```bash
hasura migrate apply --database-name default
```

---

## 2. Track the Table and Set Permissions

Open the Hasura Console (`http://localhost:8080/console`) or edit the metadata YAML directly.

### Via Console

1. **Data → default → Untracked tables** → click **Track** next to `posts`
2. **Data → posts → Permissions** → add role `user`:
   - **Insert**: allow columns `title`, `body`; column presets: `created_by = X-Hasura-User-Id`, `updated_by = X-Hasura-User-Id`
   - **Select**: filter `{ "deleted_at": { "_is_null": true } }` + filter `{ "created_by": { "_eq": "X-Hasura-User-Id" } }` for row-level access
   - **Update**: allow columns `title`, `body`; column preset: `updated_by = X-Hasura-User-Id`
   - **Delete**: use soft delete via a mutation, never grant hard delete

### Via Metadata YAML

Export the metadata after using the Console:

```bash
hasura metadata export
```

This writes `hasura/metadata/databases/default/tables/public_posts.yaml`. Commit both the migration files and the metadata changes.

---

## 3. Write the NestJS Handler (for custom logic)

Skip this step for plain CRUD — Hasura handles that automatically.

When you need custom business logic (sending email on post creation, computing derived values, etc.):

```bash
cd nestjs/
```

Create the module:

```
nestjs/src/posts/
├── posts.module.ts
├── posts.service.ts
└── posts.action.ts      ← Hasura Action handler
```

**`posts.action.ts`:**

```typescript
import { Controller, Post, Body, UseGuards } from '@nestjs/common';
import { HasuraWebhookGuard } from '../common/guards/hasura-webhook.guard.js';
import { PostsService } from './posts.service.js';

@Controller('actions')
@UseGuards(HasuraWebhookGuard)
export class PostsAction {
  constructor(private readonly postsService: PostsService) {}

  @Post('publish-post')
  async publishPost(@Body() body: any) {
    const { input, session_variables } = body;
    const userId = session_variables['x-hasura-user-id'];
    return this.postsService.publish(input.postId, userId);
  }
}
```

Register in `app.module.ts`:

```typescript
import { PostsModule } from './posts/posts.module.js';

@Module({ imports: [..., PostsModule] })
export class AppModule {}
```

---

## 4. Register the Hasura Action

Add the Action definition to `hasura/metadata/actions.yaml`:

```yaml
  - name: publishPost
    definition:
      arguments:
        - name: postId
          type: uuid!
      kind: synchronous
      handler: '{{NESTJS_WEBHOOK_URL}}/actions/publish-post'
      forward_client_headers: true
      headers:
        - name: x-hasura-event-secret
          value_from_env: HASURA_EVENT_SECRET
      output_type: PublishPostOutput
    permissions:
      - role: user
```

Add the SDL to `hasura/metadata/actions.graphql`:

```graphql
type Mutation {
  publishPost(postId: uuid!): PublishPostOutput
}

type PublishPostOutput {
  id: uuid!
  publishedAt: timestamptz!
}
```

Add the custom type to `actions.yaml` under `custom_types.objects`:

```yaml
    - name: PublishPostOutput
      fields:
        - name: id
          type: uuid!
        - name: publishedAt
          type: timestamptz!
```

Apply the metadata:

```bash
hasura metadata apply
```

---

## 5. Run and Verify

```bash
# Start the stack
make up

# Run tests
make test
```

Test the Action from the Hasura Console (`API → GraphiQL`):

```graphql
mutation {
  publishPost(postId: "some-uuid") {
    id
    publishedAt
  }
}
```

Use the `x-hasura-role: user` and `x-hasura-user-id: <your-user-id>` headers.

---

## Checklist

- [ ] Migration: `up.sql` and `down.sql` written and applied
- [ ] Table tracked in Hasura metadata
- [ ] Permissions defined for all relevant roles
- [ ] NestJS handler written (if custom logic needed)
- [ ] Hasura Action registered in `actions.yaml` + `actions.graphql` (if NestJS handler)
- [ ] `docs/test-use-cases.md` updated with new test cases
- [ ] `make test` passes

---

*See also: [Adding Tables](./adding-tables.md) · [Adding Resolvers](./adding-resolvers.md) · [Authentication](./authentication.md)*
