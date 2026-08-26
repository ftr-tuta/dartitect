# Provider fixtures

- Dio: use the real Dio adapter/interceptor boundary with mock transport; test
  cancellation, concurrency, typed failure, minimal attributes, propagation,
  and duplicate instrumentation without network.
- ObjectBox: use consumer-generated entities/model/Store/query/watcher; test
  transactions, same-path locking, cleanup, and isolate attachment on supported
  native hosts.
- Sentry: use a fake Hub, no DSN and zero network; test sanitized mapping,
  destination failure, duplicate capture prevention, and borrowed lifetime.
- Custom providers: pair deterministic contract tests with at least one real SDK
  boundary fixture that proves version and lifecycle compatibility.
