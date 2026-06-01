# Backlog

## Code Fixes
- [ ] M2: Register storage actions into `hasura/metadata/actions.yaml` + `actions.graphql` (currently empty — NestJS handlers exist but Hasura has no action definitions)
- [ ] M3: Fix `nestjs/codegen.ts` hardcoded `localhost:8080` → read from env `HASURA_GRAPHQL_ENDPOINT`

## Docs To Write
- [ ] W1: `docs/adding-feature.md` — end-to-end guide: migration → permissions → NestJS handler → Hasura action → test
- [ ] W2: Add Event Trigger setup section to `docs/adding-resolvers.md` (Console setup, local test, debug)
- [ ] W3: Add Action test workflow to `docs/adding-resolvers.md` (how to call from GraphQL client, how to debug)
- [ ] W4: `docs/authentication.md` — JWT claims structure, session variables flow, login pattern
- [ ] W5: Document `HasuraWebhookGuard` scope — which handlers need it and why
