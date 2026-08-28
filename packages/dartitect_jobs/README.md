# dartitect_jobs

`dartitect_jobs` provides provider-neutral contracts for bounded headless work.
Each accepted job receives a fresh `OwnedGraph`, cooperative cancellation, an
absolute deadline, an execution ID, and typed progress. Dispatchers retain only
a bounded deduplication window.

Optional receipt-store and lease ports let applications add durable
deduplication and fenced execution. Scheduling, recurrence, native platform
registration, credentials, payload schemas, and retries remain consumer-owned.

```dart
final dispatcher = JobDispatcher<MyPayload, int, MyFailure, MyProgress>(
  definitions: [
    JobDefinition(
      name: 'refresh',
      createGraph: buildRefreshGraph,
    ),
  ],
);
```

See the repository guides for ownership and lifecycle rules.
