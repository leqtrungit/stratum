# Adding Tables to Stratum

> This guide explains how to add new database tables to a Stratum project using Hasura migrations and the Hasura CLI.

---

## Overview

In Stratum, **all schema changes are managed through Hasura migrations**. Never modify the database directly with raw SQL outside of this workflow — doing so will cause Hasura metadata to become out of sync.

The workflow is:
1. Create a new migration (SQL up/down)
2. Apply the migration
3. Track the table in Hasura
4. Define permissions
5. Commit migration and metadata to git

---

## Auditable Fields Convention

> **This is a mandatory convention.** All standard tables in Stratum must include the full set of auditable fields.

Every table **must** have these 6 fields unless it qualifies as an exception:

| Field | Type | Description |
|---|---|---|
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Timestamp when the record was created |
| `created_by` | `UUID REFERENCES public.users(id)` | User who created the record |
| `updated_at` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | Timestamp of the last update (auto-updated via trigger) |
| `updated_by` | `UUID REFERENCES public.users(id)` | User who last updated the record |
| `deleted_at` | `TIMESTAMPTZ` | Soft-delete timestamp; `NULL` means the record is active |
| `deleted_by` | `UUID REFERENCES public.users(id)` | User who soft-deleted the record |

### Soft Delete Behavior

- **Never hard-delete** records from auditable tables. Use `deleted_at` + `deleted_by` instead.
- Add a Hasura permission filter on all roles to exclude soft-deleted rows: `{ "deleted_at": { "_is_null": true } }`
- Only `admin` role (or a dedicated system role) should be able to query deleted records.

### Exceptions — Tables That Do NOT Need Audit Fields

| Table Type | Example | Reason |
|---|---|---|
| **Junction / pivot tables** | `user_roles`, `post_tags` | Relationship-only, no lifecycle of their own |
| **Lookup / enum tables** | `countries`, `currencies` | Static reference data, managed by migrations |
| **Event log tables** | `audit_logs`, `webhook_logs` | Append-only by nature; no updates or deletes |
| **System / internal tables** | `schema_migrations` | Managed by tools, not application code |

When creating an exception table, add a SQL comment to document why:

```sql
-- Junction table: no audit fields required
CREATE TABLE public.user_roles ( ... );
```

---

## Prerequisites

- The stack is running: `docker compose up -d`
- Hasura CLI is installed: `npm install -g hasura-cli` (or via the Hasura docs)
- You have access to the Hasura Console at `http://localhost:8080`

---

## Method 1: Via Hasura Console (Recommended for Development)

### Step 1: Open the Hasura Console

```bash
cd hasura/
hasura console --admin-secret <your-admin-secret>
```

Or navigate directly to `http://localhost:8080/console` (dev mode only).

### Step 2: Create the Table

1. Go to **Data → Create Table**
2. Define your columns, primary key, and any default values
3. Click **Add Table**

Hasura will automatically create a migration file in `hasura/migrations/`.

### Step 3: Track Relationships

If your table has foreign keys:
1. Go to **Data → [your table] → Relationships**
2. Click **Add** next to the detected relationships
3. Name them (e.g., `user`, `posts`)

### Step 4: Set Permissions

1. Go to **Data → [your table] → Permissions**
2. Define row-level access for each role (e.g., `user`, `anonymous`, `admin`)
3. Set column-level permissions as needed

### Step 5: Export Metadata

```bash
cd hasura/
hasura metadata export
```

### Step 6: Commit to Git

```bash
git add hasura/migrations/ hasura/metadata/
git commit -m "feat: add [table-name] table with permissions"
```

---

## Method 2: Via SQL Migration File (Recommended for Teams / CI)

### Step 1: Create a Migration

```bash
cd hasura/
hasura migrate create "add_[table_name]_table" --database-name default
```

This creates a directory in `hasura/migrations/default/<timestamp>_add_[table_name]_table/` with `up.sql` and `down.sql`.

### Step 2: Write the Migration SQL

**`up.sql`** (apply):
CREATE TABLE public.[table_name] (
  id          UUID        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,

  -- your business columns here
  name        TEXT        NOT NULL,

  -- auditable fields (mandatory)
  -- created_at/updated_at: DEFAULT NOW() as initial value; updated_at is kept current by Hasura preset
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by  UUID        REFERENCES public.users(id) ON DELETE SET NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_by  UUID        REFERENCES public.users(id) ON DELETE SET NULL,
  deleted_at  TIMESTAMPTZ,
  deleted_by  UUID        REFERENCES public.users(id) ON DELETE SET NULL
);

COMMENT ON TABLE public.[table_name] IS '[Brief description of what this table stores]';
```

**`down.sql`** (rollback):
```sql
DROP TABLE IF EXISTS public.[table_name];
```

### Step 3: Apply the Migration

```bash
hasura migrate apply --database-name default
```

### Step 4: Track the Table in Hasura

```bash
hasura metadata apply
```

Then use the Hasura Console to track the table and set up relationships and permissions. Export metadata afterward:

```bash
hasura metadata export
```

### Step 5: Commit to Git

```bash
git add hasura/migrations/ hasura/metadata/
git commit -m "feat: add [table_name] table"
```

---

## Common Table Patterns

### Standard Auditable Table (Default)

Use this as the baseline for all non-exception tables:

CREATE TABLE public.[table_name] (
  id          UUID        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,

  -- business columns
  name        TEXT        NOT NULL,

  -- auditable fields
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by  UUID        REFERENCES public.users(id) ON DELETE SET NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_by  UUID        REFERENCES public.users(id) ON DELETE SET NULL,
  deleted_at  TIMESTAMPTZ,
  deleted_by  UUID        REFERENCES public.users(id) ON DELETE SET NULL
);
```

### Junction Table (Exception — no audit fields)

```sql
-- Junction table: no audit fields required
CREATE TABLE public.user_roles (
  user_id  UUID NOT NULL REFERENCES public.users(id)  ON DELETE CASCADE,
  role_id  UUID NOT NULL REFERENCES public.roles(id)  ON DELETE CASCADE,
  PRIMARY KEY (user_id, role_id)
);
```

### Foreign Keys

```sql
-- Standard FK with cascade delete
parent_id UUID NOT NULL REFERENCES public.parents(id) ON DELETE CASCADE

-- Optional FK (nullable)
parent_id UUID REFERENCES public.parents(id) ON DELETE SET NULL
```

Track the relationship in Hasura under **Relationships**.

### Audit Field Injection via Hasura Column Presets

All audit fields are handled automatically — the client never sends any of them.

| Field | Handled by | Mechanism |
|---|---|---|
| `created_at` | PostgreSQL | `DEFAULT NOW()` on INSERT |
| `created_by` | Hasura | Column Preset: `x-hasura-user-id` (INSERT) |
| `updated_at` | Hasura | Column Preset: `now()` (UPDATE) |
| `updated_by` | Hasura | Column Preset: `x-hasura-user-id` (UPDATE) |
| `deleted_at` | Client | Sent explicitly in soft-delete mutation |
| `deleted_by` | Hasura | Column Preset: `x-hasura-user-id` (UPDATE) |

Go to **Data → [table] → Permissions → [role] → Column Presets** in Hasura Console, or configure via YAML metadata:

```yaml
insert_permissions:
  - role: user
    permission:
      columns: [title, content]      # only expose business columns to client
      set:
        created_by: "x-hasura-user-id"
        updated_by: "x-hasura-user-id"
      check: {}

update_permissions:
  - role: user
    permission:
      columns: [title, content]
      set:
        updated_at: "now()"                    # auto-set timestamp
        updated_by: "x-hasura-user-id"         # auto-set from JWT
      filter:
        created_by: { _eq: "X-Hasura-User-Id" }  # user can only update their own rows
```

**Result:** The client mutation only needs to send business fields:

```graphql
# Client sends only this — no audit fields needed
mutation {
  insert_posts_one(object: { title: "Hello", content: "..." }) {
    id
    created_at
    created_by  # auto-set by Hasura from JWT
  }
}
```

### Soft Delete Pattern

For soft delete, configure a **dedicated Update permission** that restricts `_set` to only `deleted_at` and presets `deleted_by`:

```yaml
update_permissions:
  - role: user
    permission:
      columns: [title, content]          # editable columns
      set:
        updated_by: "x-hasura-user-id"
      filter:
        _and:
          - created_by: { _eq: "X-Hasura-User-Id" }
          - deleted_at: { _is_null: true }
```

The client triggers a soft delete via a regular update mutation:

```graphql
mutation SoftDelete($id: uuid!, $now: timestamptz!) {
  update_posts_by_pk(
    pk_columns: { id: $id }
    _set: { deleted_at: $now }
  ) { id }
}
```

> `deleted_by` is preset by Hasura automatically. The client only passes `deleted_at`.

Filter deleted records from all read queries (set in **select permissions** for the `user` role):

```json
{ "deleted_at": { "_is_null": true } }
```

> **Security rule:** Never expose `created_by`, `updated_by`, or `deleted_by` as writable columns in client-facing permissions. Use Column Presets exclusively for these fields.

---


## Rolling Back a Migration

```bash
cd hasura/
hasura migrate apply --down 1 --database-name default
```

---

## Checking Migration Status

```bash
hasura migrate status --database-name default
```

---

## Troubleshooting

| Issue | Solution |
|---|---|
| Migration applied but table not visible in Hasura | Run `hasura metadata apply` to sync |
| Metadata out of sync | Run `hasura metadata reload` in Console or CLI |
| Migration conflict with a teammate | Always pull latest and run `hasura migrate apply` before creating new migrations |

---

*See also: [Architecture](./architecture.md) · [Adding Resolvers](./adding-resolvers.md) · [Storage Usage](./storage-usage.md)*
