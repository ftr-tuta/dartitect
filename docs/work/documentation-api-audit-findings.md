# Documentation API audit findings

## Scope

This audit compared the root and package READMEs, public code snippets, public
entrypoints, the reviewed API snapshot, package examples, and focused tests. It
changed documentation and documentation tooling only; it did not change runtime
behavior, schemas, examples, or package versions.

## Confirmed documentation mismatches corrected here

### Mutation APIs were attributed to the foundation package

The previous `packages/dartitect/README.md` listed `MutationCommand`,
`MutationOutboxStore`, `OutboxOperation`, `CommitDisposition`, and related
offline mutation types in its public API tour. Those types are exported by
`package:dartitect_sync/dartitect_sync.dart`, not
`package:dartitect/dartitect.dart`. The foundation README no longer claims them,
and the sync README now documents the full mutation/outbox contract.

Evidence: `packages/dartitect/lib/dartitect.dart`,
`packages/dartitect_sync/lib/dartitect_sync.dart`,
`tool/api_surface.snapshot.json`, and the sync mutation tests.

The ecosystem selection matrix also described offline mutation contracts as a
foundation-package capability. It now routes durable mutation/outbox work to
`dartitect_sync` and keeps the foundation row limited to its real exports.

### Experimental Git instructions described an unavailable channel

The previous root README instructed consumers to use `v1.0.0-rc.4` as a
protected Git tag even though `tool/rc_candidate_contract.json` records that the
tag is not materialized and has no GitHub Release. The documentation now states
that supported experimental consumption requires a tag with a corresponding
published GitHub Release and coordinates copied from that Release's notes. When
no compatible Release exists, there is no supported consumption path.

This is a documentation/release-state mismatch; no tag or Release was created.

### The testing README linked to a non-existent managed-skill reference

The previous `dartitect_testing` README linked to
`dartitect-testing/references/test-matrix.md`. The canonical managed skill has
separate `runtime-and-reactive.md`, `sync.md`, `provider-fixtures.md`, and
`tooling.md` references and generates no `test-matrix.md` file. The package
README now links to public guides instead of a generated internal path.

### The design skill referred to a non-existent Material entrypoint

The canonical selection matrix referred to separate reactive/Material
entrypoints. The public API contains the thin Flutter entrypoint and the opt-in
reactive entrypoint only; Material and Cupertino presentation remain
consumer-owned. The canonical skill now names only the real reactive entrypoint.

## Clarifications made without a production defect

- Drift snippets now identify database methods, schema, migrations, and executor
  creation as consumer-owned while using the real `DriftDatabaseOwner` and
  `DriftMutationTransaction` APIs.
- Sync documentation now separates durable mutation/outbox, dataset DAG runs,
  and headless command delivery, and explains that application/checkpoint/
  journal/release/cleanup receipts must be inspected independently.
- ObjectBox documentation now distinguishes query watchers from Store watches,
  documents `Store.runAsync` projection and Store-reference attachment, and
  states the complete teardown order.
- All package READMEs now identify actual public entrypoints and supported
  platforms, including the two Flutter entrypoints and the analyzer-only
  `dartitect_lints` entrypoint.

## Audit evidence

The reviewed `tool/api_surface.snapshot.json` was checked against all 20 public
entrypoints after the rewrite. Each minimal workflow was traced to its package
example or focused public-boundary tests:

- foundation, Flutter, modeling, modeling analyzer, isolates, observability,
  Dio, Sentry, privacy, media, locale, geometry, and testing use their existing
  package examples and corresponding package tests;
- sync uses the dataset example plus mutation, engine, headless, and persisted-
  compatibility tests;
- Drift uses the executor-neutral example and generated test database covering
  ownership, transactions, streams, checkpoints, journals, and instrumentation;
- ObjectBox uses its generated example and native generated-model fixture for
  queries, watches, projections, transactions, Store references, and teardown;
- CLI and lints use their documented executable/plugin entrypoints and focused
  synchronizer/parity tests; and
- MCP uses the package example plus the in-process and real-STDIO client tests.

Consumer-specific names in persistence snippets (database class, executor,
migration check, entity, and generated `openStore`) are explicitly identified
as consumer-owned extension points, not Dartitect APIs.

## Production follow-up

No production implementation defect was confirmed during this documentation
audit. If later validation exposes behavior that contradicts the corrected
contracts, it must be handled as a separate production change with focused
tests; it is outside this documentation-only task.
