# Task: Fix Hasura Migration Script

## Problem
The `hasura-apply-migrations` service fails with `hasura: command not found`. This is because the `hasura/graphql-engine:v2.44.0.cli-migrations-v3.ubuntu` image might not have `hasura` in the PATH, or it's named differently (e.g., `hasura-cli`).

## Plan
- [x] Identify the correct Hasura CLI binary name/path in the `cli-migrations` image.
- [x] Update `hasura/apply-migrations.sh` to use the correct binary (`hasura-cli`).
- [x] Verify the fix by running `docker compose up hasura-apply-migrations`.
- [x] Refactor metadata to standard Hasura V3 format (split tables, added `version.yaml`).
- [x] Improve script robustness for empty seed directories.

## Progress
- [x] Investigate binary name
- [x] Apply fix
- [x] Verify
- [x] Standardize setup
