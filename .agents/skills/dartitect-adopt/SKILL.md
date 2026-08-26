---
name: dartitect-adopt
description: Inventory and migrate an existing Dart or Flutter codebase to Dartitect incrementally with reviewed baselines and explicit boundaries. Use for brownfield adoption; do not use for greenfield stack selection or isolated implementation.
---

# Adopt Dartitect

## When to use

Use this skill when existing architecture, globals, providers, violations, or
lifecycle assumptions must be discovered before Dartitect can be introduced.

## When not to use

Use `$dartitect-design` for a new application or feature. After the migration
slice is defined, use the focused skill responsible for its implementation.

## Invariants

Inspect before changing code. Preserve behavior, migrate one explicit boundary
at a time, and distinguish pre-existing debt from new violations. Never use a
baseline to hide unreviewed findings, convert a generic catch into success, move
live resources across isolates, edit generated files, or introduce global
Store, Dio, telemetry, or runtime state.

## Workflow

1. Record tests, analyzer, `dartitect doctor`, and
   `dartitect scan --no-baseline` before migration.
2. Inventory composition roots, owners, disposal order, repositories,
   background entrypoints, provider SDKs, and telemetry paths.
3. Select one vertical slice with explicit compatibility and rollback limits.
4. Introduce constructor injection, typed failures, ownership, and tests before
   moving to another slice.
5. Create a baseline only for reviewed remaining debt and remove stale entries.

For discovery, read [references/inventory.md](references/inventory.md). For the
migration sequence and CLI/MCP boundaries, read
[references/incremental-migration.md](references/incremental-migration.md).

## Validate

Compare the post-slice tests, analyzer, doctor, and unbaselined scan with the
recorded baseline. Confirm the slice has one owner, reverse disposal, no new
global/provider leakage, and a smaller or unchanged reviewed-debt set.
