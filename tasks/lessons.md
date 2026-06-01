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
