# Provider fixtures

- Dio: use the real Dio adapter/interceptor boundary with mock transport; test
  cancellation, concurrency, typed failure, minimal attributes, propagation,
  and duplicate instrumentation without network.
- Drift: use a consumer-generated test database and real executor; test owned
  and borrowed close, failed configuration cleanup, commit/rollback, watches,
  checkpoint/journal fencing, migration/reopen, and web worker/assets where
  applicable.
- ObjectBox: use consumer-generated entities/model/Store/query/watcher; test
  transactions, same-path locking, cleanup, and isolate attachment on supported
  native hosts.
- Sentry: use a fake Hub, no DSN and zero network; test sanitized mapping,
  prepared-input no-double-redaction, defensive legacy mapping, no automatic
  `SentryUser`, destination failure, duplicate capture prevention, and borrowed
  lifetime.
- Observability privacy: run strict/balanced/diagnostic matrices across local,
  remote, and named destinations; assert `deny > mask > allow`, raw-secret
  absence, cycles, key collisions, Unicode bounds, structural budgets,
  independent slow/failing queues, ownership, snapshots, and detailed flush.
- Custom providers: pair deterministic contract tests with at least one real SDK
boundary fixture that proves version and lifecycle compatibility.
