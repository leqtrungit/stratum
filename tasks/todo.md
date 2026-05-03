# Task: Debug Missing Hasura Actions

## Problem
The user reports that actions in `hasura/metadata/actions.yaml` do not appear in Hasura after applying metadata and migrations.

## Root Cause
1. `hasura/metadata/version.yaml` was missing.
2. `actions.yaml` was a list instead of a map with the `actions:` key.
3. `actions.graphql` was missing, which is required for SDL definitions in split metadata mode.
4. `custom_types` were not properly integrated into the standard structure.

## Plan
- [x] Verify the current metadata status using `hasura metadata apply --dry-run`.
- [x] Initialize a standard Hasura project for structure comparison (`hasura init`).
- [x] Reconstruct `hasura/metadata` to follow standard CLI v3 structure.
- [x] Merge `custom_types` into `actions.yaml` as per standard format.
- [x] Create `actions.graphql` with full SDL (Mutation + Type definitions).
- [x] Verify fix with `hasura metadata diff`.
- [x] Apply metadata successfully.

## Progress
- [x] Investigating metadata structure
- [x] Fixing missing files
- [x] Verifying actions appearance
- [x] Successfully applied metadata

## Review
- Metadata is now in a standard, recognizable format.
- Actions and Custom Types are visible in Hasura console.
- SDL is properly tracked in `actions.graphql`.
