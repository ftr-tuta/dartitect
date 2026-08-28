# Dartitect implementation recipes

## Before copying a recipe

These recipes are composition sketches derived from the repository's tested
public APIs and examples. Replace the consumer-owned contracts, failures,
entities, repositories, and providers; keep Dartitect ownership and causal
boundaries intact. Choose the stack first with the
[ecosystem selection guide](ecosystem-selection.md).

## Simple feature

For pure Dart, start with typed expected failure and one explicit owner:

```dart
final owner = ResourceOwner(label: 'FeatureRuntime')
  ..own(StreamController<void>(), (controller) => controller.close());

final Result<int, StateError> result = const Ok<int>(42);
switch (result) {
  case Ok(:final value): print(value);
  case Err(:final failure): print('Expected: $failure');
}

await owner.disposeAsync();
```

At a basic Flutter boundary, keep the ViewModel owned by the host and keep
`BuildContext` out of it:

```dart
ViewModelHost<CounterViewModel>.create(
  create: CounterViewModel.new,
  builder: (context, counter) => ListenableBuilder(
    listenable: counter,
    builder: (context, child) => Text('${counter.value}'),
  ),
);
```

Use `ViewModelHost.value` instead when the route/composition root owns the
ViewModel. The complete examples are
[`dartitect_example.dart`](../../packages/dartitect/example/dartitect_example.dart)
and
[`dartitect_flutter_example.dart`](../../packages/dartitect_flutter/example/dartitect_flutter_example.dart).

## Reactive runtime

Create the resource at a route/session composition boundary. The source factory
owns each activation-local session and borrows any injected provider:

```dart
final local = LiveResource<PagedLocalSnapshot<int, Task>, TaskFailure>(
  source: TaskStoreSource(store),
  policy: const ActivationPolicy.whileObserved(),
);
```

Choose hot/warm/cold policy and backpressure as feature contracts. In Flutter,
the widget borrows the resource:

```dart
LiveResourceBuilder<PagedLocalSnapshot<int, Task>, TaskFailure>(
  resource: local,
  builder: (context, state, temperature, isStale, child) =>
      Text(state.hasData ? '${state.lastData}' : 'Loading'),
);
```

Dispose consumers before their source: `await paged.dispose();` then
`await local.dispose();`. Keep rendering in consumer presentation. See the
complete [headless reactive example](../../packages/dartitect_flutter/example/reactive_offline_first_example.dart)
and the Material composition in the reference workloads.

## Local-first pagination

`PagedLiveResource` writes every remote page through the repository and waits
for the exact local revision before advancing its cursor:

```dart
final paged = PagedLiveResource<Cursor, int, Task, TaskFailure>(
  local: local,
  initialCursor: const Cursor(),
  requestPage: remote.requestPage,
  writePage: repository.writePage,
  keyOf: (task) => task.id,
  versionOf: (task) => task.version,
  collectionPolicy: CollectionUpdatePolicy.versionedByKey,
  observationTimeout: const Duration(seconds: 3),
  mapObservationTimeout: (_) => const TaskObservationTimeoutFailure(),
);
```

The repository transaction returns `PageWriteReceipt.localRevision`; only the
borrowed `LiveResource<PagedLocalSnapshot<...>>` may publish presentation data.
Refresh joins an active refresh, load-more drops reentry, and search is
restart-latest. Check cancellation before local write. The in-memory example
contains a complete
[`ReactiveSource` and `PagedLiveResource`](../../packages/dartitect_flutter/example/reactive_offline_first_example.dart);
the reference app supplies a provider-backed implementation.

## Mutation and outbox

The consumer store atomically changes domain state and persists the outbox in
`MutationOutboxStore.applyLocalAndEnqueue`. Compose per-key delivery like this:

```dart
var sequence = 0;
final mutations = MutationCommand<TaskMutation, int, void, TaskFailure>(
  store: store,
  synchronize: remote.synchronize,
  createIdempotencyKey: (key, argument) {
    sequence += 1;
    return 'task-$key-$sequence';
  },
  classifyFailure: classifyTaskFailure,
  reporter: crashReporter,
);
```

The idempotency key is non-empty and reused by retry. Persist remote
acknowledgement before declaring the operation synced. Map expected failures to
queued, rejected, conflicted, or uncertain. Compensate only a definitive
rejection. After a possible remote commit or crash, audit durable state before
marking pending and calling `resume(key)`. A new session calls
`recoverPending()` but does not deliver uncertain records automatically.

Use the tested
[`OfflineFirstTaskSession`](../../examples/reference_app/lib/features/tasks/application/offline_first_task_session.dart)
and its memory/ObjectBox stores as the complete recipe.

## Observability

Start local and provider-neutral:

```dart
final telemetry = ObservabilityRuntime();
try {
  telemetry.logger.info('Application started.');
  // Inject telemetry.reporter and telemetry.tracing into consumers.
} finally {
  await telemetry.disposeAsync();
}
```

Before adding a destination, define an allowlist and redaction policy. Never
record credentials, authorization, cookies, bodies, headers, queries, DSNs,
identity, or identifying paths. Expected `Err` values remain command state;
unexpected crashes may be reported once and are rethrown. Install one
`FlutterErrorBinding`, chain/restore previous handlers, and transfer only valid
W3C trace context between isolates.

For reactive diagnostics, inject a bounded `ReactiveJournal` locally or a
`ReactiveObserverLoggerAdapter`; events never carry domain payloads, keys, error
text, or identity. See the
[observability example](../../packages/dartitect_observability/example/dartitect_observability_example.dart)
and [observability guide](observability.md).

## Adapter composition

Create only adapters selected by the application, inside infrastructure
composition:

```dart
final dioOwner = DioOwner.create();
final driftOwner = await DriftDatabaseOwner.create<AppDatabase>(
  openDatabase: openConsumerDatabase,
);
final objectBoxOwner = await ObjectBoxStoreOwner.create(openStore: openStore);
final telemetry = ObservabilityRuntime(
  logSinks: <LogSinkRegistration>[
    LogSinkRegistration.borrowed(SentryLogSink(hub: consumerOwnedHub)),
  ],
);

try {
  final dio = dioOwner.dio;
  final database = driftOwner.database;
  final store = objectBoxOwner.store;
  // Inject application-owned interfaces implemented with dio/database/store.
} finally {
  dioOwner.dispose();
  await driftOwner.disposeAsync();
  await objectBoxOwner.disposeAsync();
  await telemetry.disposeAsync();
  // The consumer closes consumerOwnedHub afterward.
}
```

Most applications need only one or two of these adapters. Dio exposes typed
cancellation/transport/HTTP/configuration failures and minimal telemetry.
Drift borrows a consumer-generated database type: the application owns tables,
migrations, DAOs, executor selection, native paths, web worker/WASM assets, and
storage policy. Adapt `Selectable.watch()` with `StreamReactiveSource`.
ObjectBox entities/model/codegen remain consumer-owned and it has no web
support. Sentry borrows an already initialized Hub. Reject duplicate
instrumentation. Follow the provider examples for
[Dio](../../packages/dartitect_dio/example/dartitect_dio_example.dart),
[Drift](../../packages/dartitect_drift/example/dartitect_drift_example.dart),
[ObjectBox](../../packages/dartitect_objectbox/example/dartitect_objectbox_example.dart),
and [Sentry](../../packages/dartitect_sentry/example/dartitect_sentry_example.dart).

When Drift and ObjectBox coexist, put them in distinct bounded contexts. Keep
repositories separate, dispose observations/sync/repositories before either
database, and allow one writer per dataset or partition. Do not dual-write,
bridge engines, or imply a cross-engine transaction; migrate data explicitly.

## Owned graph and atomic swap

Build related resources transactionally and publish only a complete root:

```dart
final slot = OwnedRuntimeSlot<Api>(label: 'session');
await slot.replace((transaction) async {
  final client = transaction.own(Api(), (value) => value.close());
  return client;
});
await slot.use((api) => api.refresh());
await slot.disposeAsync();
```

Register owned values immediately after acquisition and borrowed values with
`transaction.borrow`. A failed replacement rolls back in reverse order and
leaves the previous generation current. Disposal rejects new operations, drains
admitted work, and only then closes resources.

## Local snapshot presentation

Repositories publish `ResourceSnapshot<T, M>` only after the local transaction
is authoritative. Flutter maps the enclosing reactive state with
`toPresentation(isEmpty: ...)`; the result is waiting, content, empty, or
failure. The mapping performs no fetch or write and preserves expected failures
separately from crashes and their original stacks.

## Foreground and headless sync

Model datasets and their prerequisites with `SyncDependencyGraph`. A
`SyncEngine` reads confirmed checkpoints, executes stable plan order, persists a
new checkpoint with the active fencing token, and lets independent branches
continue when another branch fails. With a configured lease, the dataset
receives `SyncAuthority`; ensure it immediately before the local transaction and
atomically compare/commit its fencing token in a capable store. The engine does
not promise dataset fencing when storage cannot enforce that transaction.
Unexpected terminal failure carries a `SyncRunTerminalException` report with
separate application, checkpoint, journal, lease-release, and cleanup receipts;
inspect it before retry. Scheduling, retry, conflict, provider
transactions, and authentication remain application policy. For background
delivery, validate a versioned `SyncCommandEnvelope`, build a fresh `OwnedGraph`
inside `HeadlessSyncEndpoint`, acknowledge acceptance, deduplicate request IDs,
and await the terminal ACK.

The complete provider-free workload is
[`dartitect_sync_example.dart`](../../packages/dartitect_sync/example/dartitect_sync_example.dart).

## Validation

For every recipe, test success, typed failure, unexpected rethrow, cancellation
or concurrency, disposal order, and zero residual subscriptions/timers/queries/
isolates. Use deterministic fakes for policy and a real generated/provider
fixture for SDK compatibility. Run analyzer, focused tests, `dartitect scan
--no-baseline`, and `dartitect doctor`; use a reviewed baseline only for existing
debt.
