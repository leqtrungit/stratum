# Authentication in Stratum

> This document explains how JWT authentication works in Stratum — the claims structure, how session variables flow from client to Hasura to NestJS, and the login pattern.

---

## Overview

Stratum uses **JWT (JSON Web Tokens)** for authentication. The flow is:

1. Client authenticates (login mutation or external auth provider) and receives a JWT
2. Client includes the JWT in every GraphQL request: `Authorization: Bearer <token>`
3. Hasura validates the JWT signature and extracts **Hasura claims**
4. Hasura maps claims to **session variables** used in row-level permissions
5. When Hasura calls NestJS (Actions, Event Triggers), it forwards session variables in the request body

NestJS never issues or validates JWTs — that is Hasura's responsibility.

---

## JWT Claims Structure

Every JWT must include a `https://hasura.io/jwt/claims` namespace with Hasura-specific claims:

```json
{
  "sub": "user-uuid-here",
  "email": "user@example.com",
  "iat": 1700000000,
  "exp": 1700086400,
  "https://hasura.io/jwt/claims": {
    "x-hasura-default-role": "user",
    "x-hasura-allowed-roles": ["user"],
    "x-hasura-user-id": "user-uuid-here"
  }
}
```

| Claim | Required | Description |
|---|---|---|
| `x-hasura-default-role` | Yes | Role used when the client does not specify a role |
| `x-hasura-allowed-roles` | Yes | All roles this user is allowed to adopt |
| `x-hasura-user-id` | Yes | The user's UUID — used for row-level permission filters |

### JWT Secret Configuration

The JWT secret is set in `.env`:

```env
HASURA_GRAPHQL_JWT_SECRET={"type":"HS256","key":"your-secret-min-32-chars"}
```

Use `HS256` (symmetric) for simple setups. For production, consider `RS256` (asymmetric) with a public key.

---

## Session Variables

When Hasura executes a query on behalf of a client, it makes session variables available:

| Session Variable | Source | Example |
|---|---|---|
| `X-Hasura-Role` | JWT claim `x-hasura-default-role` or client header | `user` |
| `X-Hasura-User-Id` | JWT claim `x-hasura-user-id` | `550e8400-...` |
| `X-Hasura-Allowed-Roles` | JWT claim `x-hasura-allowed-roles` | `["user"]` |

### Using Session Variables in Hasura Permissions

Example — users can only select their own rows:

```yaml
# In public_posts.yaml permission filter
filter:
  created_by:
    _eq: X-Hasura-User-Id
```

Example — column preset on insert (auto-sets `created_by`):

```yaml
set:
  created_by: X-Hasura-User-Id
  updated_by: X-Hasura-User-Id
```

### Accessing Session Variables in NestJS

When Hasura calls a NestJS Action or Event Trigger, it includes session variables in the request body:

```typescript
@Post('my-action')
async myAction(@Body() body: any) {
  const { input, session_variables } = body;

  // Session variables are lowercase in the NestJS body
  const userId = session_variables['x-hasura-user-id'];
  const role   = session_variables['x-hasura-role'];
}
```

---

## Login Pattern

Stratum does not ship a built-in login mutation — authentication is intentionally decoupled so you can plug in your own strategy.

### Recommended Pattern: Custom NestJS Action

1. **Client calls** `mutation login(email, password)` via Hasura
2. **Hasura delegates** to NestJS `/actions/login`
3. **NestJS** verifies credentials, signs a JWT, returns it
4. **Client** stores the JWT and includes it in all subsequent requests

**Example NestJS handler (sketch):**

```typescript
import * as jwt from 'jsonwebtoken';

@Post('login')
async login(@Body() body: any) {
  const { email, password } = body.input;

  const user = await this.usersService.findByEmail(email);
  if (!user || !await bcrypt.compare(password, user.passwordHash)) {
    throw new UnauthorizedException('Invalid credentials');
  }

  const token = jwt.sign(
    {
      sub: user.id,
      email: user.email,
      'https://hasura.io/jwt/claims': {
        'x-hasura-default-role': 'user',
        'x-hasura-allowed-roles': ['user'],
        'x-hasura-user-id': user.id,
      },
    },
    process.env.JWT_SECRET!,
    { expiresIn: '24h' },
  );

  return { token };
}
```

> This handler does **not** need `HasuraWebhookGuard` because the login endpoint is unauthenticated by design. Remove `@UseGuards(HasuraWebhookGuard)` from it, or create a separate controller for public actions.

---

## Role Escalation Prevention

Hasura enforces that the role in `X-Hasura-Role` must appear in the JWT's `x-hasura-allowed-roles`. If the client tries to use a role not in that list, Hasura rejects the request — you cannot escalate to `admin` without it being in the token.

Never add `admin` to `x-hasura-allowed-roles` for regular users.

---

## Checklist for New Features

- [ ] New tables have row-level permission filters using `X-Hasura-User-Id`
- [ ] Insert permissions include column presets for `created_by` and `updated_by`
- [ ] NestJS Action handlers extract `userId` from `session_variables['x-hasura-user-id']`
- [ ] No endpoint that should be authenticated is missing `HasuraWebhookGuard`

---

*See also: [Architecture](./architecture.md) · [Adding Resolvers](./adding-resolvers.md) · [Adding Feature](./adding-feature.md)*
