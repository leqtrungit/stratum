# Backlog

## Code Fixes
- [x] M2: Register storage actions into `hasura/metadata/actions.yaml` + `actions.graphql` (already done in Phase 2)
- [x] M3: Fix `nestjs/codegen.ts` hardcoded `localhost:8080` → read from env `HASURA_GRAPHQL_ENDPOINT`

## Docs To Write
- [x] W1: `docs/adding-feature.md` — end-to-end guide: migration → permissions → NestJS handler → Hasura action → test
- [x] W2: Add Event Trigger setup section to `docs/adding-resolvers.md` (Console setup, local test, debug)
- [x] W3: Add Action test workflow to `docs/adding-resolvers.md` (how to call from GraphQL client, how to debug)
- [x] W4: `docs/authentication.md` — JWT claims structure, session variables flow, login pattern
- [x] W5: Document `HasuraWebhookGuard` scope — which handlers need it and why

## Planned: bootstrap.sh — `template/` directory separation

**Problem:** `bootstrap.sh` hiện dùng hardcoded exclude list (`STRATUM_INTERNAL`) để xóa file internal khỏi project của user. Dev thêm file internal mới sẽ không biết phải update list này.

**Solution:** Dùng thư mục `template/` — bootstrap chỉ lấy những gì bên trong đó, mọi thứ ngoài tự động excluded. Không cần maintain list.

```
stratum/
├── template/       ← CHỈ cái này đến tay user
│   ├── hasura/
│   ├── nestjs/
│   ├── docs/
│   └── ...
├── .github/        ← tự động excluded
├── tests/          ← tự động excluded
└── bootstrap.sh    ← tự động excluded
```

**Scope:** restructure repo, update `bootstrap.sh` để extract từ `template/` thay vì root.
