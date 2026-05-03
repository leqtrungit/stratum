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

## Workflow Orchestration
- **Commit Granularity**: Separate changes into logical commits (e.g., Infrastructure, Core API, Feature Module, Docs) to maintain a clean and searchable history.
- **Plan First**: Always update `tasks/todo.md` and check-in with the user before starting major implementation phases.
