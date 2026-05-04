# Task: Fix Hasura Metadata Apply Fatal Error

## Problem
Running `bootstrap.sh` with `S3_ENABLED=n` and then `docker compose up -d` results in a fatal error in the `hasura-apply-migrations` service:
`level=fatal msg="error applying metadata \n{\n  \"error\": \"key \\\"tables\\\" not found\",\n  \"path\": \"$.args.metadata\",\n  \"code\": \"parse-failed\"\n}"`

## Root Cause Analysis
1. **Missing `version.yaml`**: The file `hasura/metadata/version.yaml` is in `.gitignore`. Since `bootstrap.sh` downloads the project via a tarball from Git, ignored files are excluded. Without `version.yaml`, Hasura CLI defaults to Metadata V2, which fails to parse the V3 project structure.
2. **Directory Permissions**: The `hasura/metadata/databases` directory is created/copied with `744` permissions, preventing the non-root Hasura CLI user in Docker from entering the directory to resolve `!include` references.
3. **Improper Apply Order**: `apply-migrations.sh` applies migrations before metadata. In Hasura V3, metadata should be applied first so that all database sources are connected before running migrations against them.

## Action Items
- [x] **Fix Git Configuration**
    - [x] Remove `hasura/metadata/version.yaml` from `.gitignore`.
    - [x] Force add and commit `hasura/metadata/version.yaml` to the repository.
- [x] **Optimize Hasura Setup Script**
    - [x] Update `hasura/apply-migrations.sh` to apply metadata **before** migrations.
- [ ] **Verification**
    - [ ] Run `bootstrap.sh` in a clean temporary directory.
    - [ ] Verify `version.yaml` is present.
    - [ ] Run `docker compose up -d` and verify all services start correctly.
    - [ ] Check `hasura-apply-migrations` logs for successful completion.

## Review
- [ ] No fatal errors during metadata application.
- [ ] Metadata version correctly recognized as V3.
- [ ] Permissions correctly set for Docker environment.
