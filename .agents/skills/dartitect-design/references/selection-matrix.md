# Selection matrix

- Pure Dart result/ownership/composition: `dartitect` plus `$dartitect-runtime`.
- Immutable values, explicit JSON, projections, or pure boundary mappers: add
  `dartitect_modeling` and `$dartitect-modeling`; capabilities remain separately
  opt-in and Analyzer tooling stays out of runtime.
- Basic Flutter ViewModels and commands: add `dartitect_flutter` and keep the
  established `dartitect_flutter.dart` entrypoint.
- Hot/warm/cold resources, causal refresh, families, collections, selectors, or
  advanced builders: use the opt-in reactive entrypoint and
  `$dartitect-reactive`.
- Local-authority paging or durable mutations/outbox: combine the reactive
  runtime with `$dartitect-offline-first`; add a storage adapter only after the
  application chooses its provider.
- Dataset DAG orchestration, checkpoints, leases, progress, or headless ACKs:
  add `dartitect_sync` and `dartitect_jobs` with `$dartitect-offline-first`;
  keep scheduling, recurrence, conflicts, storage transactions, and provider
  resources consumer-owned.
- Bounded retry, single-flight, breaker, bulkhead, or rate limiting: add
  `dartitect_resilience`; expected-failure classification remains
  consumer-owned and uncertain mutation results are never retried.
- Resumable chunk transfer: add `dartitect_transfer` and optionally
  `dartitect_dio`; checkpoints follow durable chunk commits, while remote
  protocol, authentication, Range, ETag, and idempotency remain consumer-owned.
- Neutral logs/reporting/tracing: add `dartitect_observability` and
  `$dartitect-observability`; add `dartitect_sentry` only for an already selected
  and consumer-initialized Sentry Hub.
- Dio, Drift, or ObjectBox integration: add only the matching adapter and use
  `$dartitect-adapters`.
- Deterministic consumer tests: add `dartitect_testing` as a dev dependency and
  use `$dartitect-testing`.
- Inspection, generators, policy, or CI gates: use `dartitect_cli` and/or
  `dartitect_lints` with `$dartitect-tooling`.
- Local bounded agent context: add `dartitect_mcp` as a dev dependency and use
  `$dartitect-mcp`; scripts should call the CLI directly.

ObjectBox has no web support. CLI and MCP run on the Dart VM. Material widgets
belong only in Material presentation code. Provider adapters never belong in
domain, application, ViewModel, or presentation layers.

For incremental adoption, an installed overlapping runtime is a warning until
evidence shows provider leakage, service location, duplicate ownership, or a
concrete boundary crossing. Select one bounded adoption slice at a time.
