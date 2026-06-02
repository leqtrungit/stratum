# Lessons & Patterns

## Testing & Maintenance
- **Rule**: Always maintain `docs/test-use-cases.md` in sync with the development process.
- **Pattern**: Whenever a new feature or change is implemented (e.g., new module, new action), the agent MUST:
  1. Update `docs/test-use-cases.md` with new/relevant test cases.
  2. Update or add corresponding automated test scripts (E2E/Unit).
  3. Verify the changes by running the tests before committing.
- **Rationale**: Ensures the boilerplate remains stable, and all use cases are clearly documented for the end-user.

## Hasura & NestJS Integration
- **ESM Modules**: In NestJS 11+ with `nodenext` configuration, local imports MUST include the `.js` extension even if the source file is `.ts`.
- **Config Null Safety**: Always use `configService.getOrThrow<string>()` for mandatory environment variables to avoid `undefined` types and ensure the app fails-fast on misconfiguration.
- **Modular Metadata**: Use comment markers (`# MODULE_START` / `# MODULE_END`) within Hasura metadata files. This allows the `install.sh` script to cleanly and programmatically remove optional features if the user opts out.
- **Hasura CLI v3 Structure**: In CLI v3 split metadata mode, `metadata/version.yaml` is mandatory. The CLI expects specific file names (`actions.yaml`, `databases/databases.yaml`, etc.) to automatically build the metadata.
- **Actions SDL Requirement**: When defining actions in split mode, Hasura CLI v3 requires an `actions.graphql` file containing the SDL definitions (Mutations/Queries and their custom types). Even if types are defined in `actions.yaml`'s `custom_types` section, they may still be required in the `.graphql` file for validation.
- **Standard Reference**: If metadata parsing fails or structure is unclear, use `hasura init <tmp_dir>` to verify the latest standard structure expected by the installed CLI version.

## Optional Module Pattern (Template Overlay)

- **Pattern**: Optional features (e.g. Storage) are managed via `.template/storage/` overlay — NOT runtime env checks.
  - Base files (`nestjs/src/app.module.ts`, `hasura/metadata/...`) = core-only version
  - `.template/storage/` = files that override base when storage is enabled
  - `install.sh` runs `cp -R .template/storage/* ./` when user enables storage
  - `install.sh` strips `# STORAGE_START/END` markers from metadata files when storage is disabled
- **Rule**: Never use `process.env.STORAGE_ENABLED` in source code to conditionally load modules. The template overlay produces the correct file at setup time — no runtime branching needed.
- **Always check `.template/` before implementing** any feature toggle or optional module logic.

## Workflow Orchestration
- **Commit Granularity**: Separate changes into logical commits (e.g., Infrastructure, Core API, Feature Module, Docs) to maintain a clean and searchable history.
- **Plan First**: Always update `tasks/todo.md` and check-in with the user before starting major implementation phases.
- **CRITICAL — Review before `git add` on hasura/**: `install.sh` deletes/strips files in `hasura/metadata/` and `hasura/migrations/` when run in core-only mode. Before staging `hasura/`, ALWAYS run `git diff --stat hasura/` and verify no files are unexpectedly deleted. If any `.yaml` or `.sql` files show as deleted, DO NOT commit — restore them first.
- **Test isolation**: Any test that runs `install.sh` in the project root MUST use `backup_files()`/`restore_files()` (temp copy approach) to protect working tree changes. Never use `git checkout --` to restore — it destroys uncommitted work.

## NestJS & Docker
- **Build Structure**: Ensure `tsconfig.build.json` excludes any `.ts` files in the root (like `codegen.ts` or `eslint.config.ts`) to prevent `tsc` from creating a nested `dist/src` folder structure. This ensures the Docker entrypoint `dist/main.js` remains correct.
- **Node.js Version**: Use **Node.js 24 (Active LTS)** for NestJS 11 projects in 2026. It provides the best balance of stability (LTS status since Oct 2025) and compatibility with modern SDKs (like AWS SDK v3 which requires Node >= 22).
- **Copy `.npmrc` before `pnpm install` in Dockerfile**: pnpm reads `.npmrc` from the working directory at install time. Always `COPY package.json pnpm-lock.yaml .npmrc ./` before `RUN pnpm install` — otherwise any pnpm config (e.g. `dangerouslyAllowAllBuilds`) is silently ignored.

## CI / GitHub Actions
- **`tr | fold -w N | head -n 1` hangs on Linux CI when run inside a pipe**: When bash itself runs inside a pipe (`echo ... | bash script.sh`), it ignores SIGPIPE. Child processes (`fold`, `tr`) inherit this and never terminate when `head -n 1` exits — the pipeline hangs forever reading `/dev/urandom`. Fix: replace `fold -w N | head -n 1` with `head -c N`. Byte-count termination doesn't rely on SIGPIPE. macOS unaffected due to different signal handling.
- **pnpm v10 `approve-builds` hangs silently in Docker**: pnpm v10 prompts interactively for packages with build scripts (`@nestjs/core`, `unrs-resolver`). With no TTY/stdin in a Docker build, the prompt blocks forever with zero output. Fix: `dangerouslyAllowAllBuilds=true` in `.npmrc`, copied into the image before install. References: pnpm/pnpm#9102, #6778.
- **Docker Compose v2.39.2+ suppresses build output**: `BUILDKIT_PROGRESS=plain` as env var is ignored by `docker compose` (docker/compose#12457, #13224). Builds are always silent in non-TTY. Use `docker compose build --progress=plain` as a dedicated step if visibility is needed.
- **GitHub Actions Node.js 24 opt-in**: Add `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: 'true'` at workflow `env` level to avoid deprecation warnings for `actions/checkout`, `actions/setup-node`, `pnpm/action-setup` ahead of the June 16, 2026 mandatory cutover.
- **Debug CI hangs: always check orphan processes in job cleanup log**: When a job is cancelled or times out, GitHub Actions lists orphaned child processes. These reveal exactly what the script was executing at the time — far faster than guessing from missing output.
