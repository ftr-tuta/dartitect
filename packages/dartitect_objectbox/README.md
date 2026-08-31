# dartitect_objectbox

## Purpose

Native ObjectBox adapters for explicit Store/query/watcher ownership, reactive
query and Store-watch sources, versioned projections, `Store.runAsync`
projection, typed transactions, sync checkpoints/journals, and sanitized
instrumentation. Consumer entities and generated ObjectBox models remain
consumer-owned.

Config-v2 generation exposes one `<Context>DartitectObjectBoxFragment` and a
frozen operational UID map. Adding or removing a feature registration does not
renumber operational entities or properties; domain entities and the generated
consumer model remain consumer-owned.

## When to use

Use it in a native infrastructure composition root after the application has
selected ObjectBox and generated a compatible model. It is useful when an owned
or borrowed Store needs deterministic observation teardown, a reactive
local-authority source, a domain-plus-outbox transaction, or `dartitect_sync`
persistence adapters.

## When not to use

Do not use it for web, before a generated consumer model exists, or as a generic
ORM/repository abstraction. Do not use it to hide entities, schema, generated
code, encryption, transport, or conflict policy.

## Platforms and entrypoints

Import `package:dartitect_objectbox/dartitect_objectbox.dart`. ObjectBox is
supported on Android, iOS, Linux, macOS, and Windows. Web is not supported.

## Mental model and data flow

A composition root opens a Store through `ObjectBoxStoreOwner.create` (owned),
wraps an existing Store with `.value` (borrowed), or uses `.temporary` in
isolated fixtures. The owner's `ObjectBoxObservationOwner` owns queries,
watchers, subscriptions, and other observation cleanup, and drains them before
an owned Store closes.

For local authority, choose the source that matches the invalidation boundary:

- `ObjectBoxQuerySource` creates a fresh consumer query builder and query watcher
  per hot activation, then runs `findAsync` by default.
- `ObjectBoxStoreWatchSource` merges one or more typed `Store.watch<E>()`
  invalidations and calls a consumer pull function. It is useful when a read
  spans entities or uses repository logic rather than one watched query.

Both borrow the Store and own activation-local observation only. Values flow
into `LiveResource`/`LiveCollection`; provider types stop at infrastructure.

## Minimal workflow

```dart
import 'package:dartitect_objectbox/dartitect_objectbox.dart';

import 'fixture_entity.dart';
import 'objectbox.g.dart';

Future<void> main() async {
  final owner = await ObjectBoxStoreOwner.temporary(
    openStore: (directory) => openStore(directory: directory),
  );
  try {
    final box = owner.store.box<FixtureEntity>();
    final id = box.put(FixtureEntity(value: 'native-first'));
    assert(box.get(id)?.value == 'native-first');
  } finally {
    await owner.disposeAsync();
  }
}
```

The package example contains a genuinely generated model. Application code uses
its own generated entity and `openStore` instead.

## Public API tour

Ownership and observation:

- `ObjectBoxStoreOwner.create` owns/open/closes a Store; `.value` borrows it;
  `.temporary` owns both a validated temporary directory and its Store.
- `ObjectBoxObservationOwner` registers synchronous or asynchronous cleanup and
  drains observations before Store teardown.
- `ObjectBoxInstrumentation` traces fixed open/close facts without provider or
  domain payloads.

Reactive sources and projections:

- `ObjectBoxQuerySource` owns one query watcher and every query it yields for
  each activation. It maps open/read failures only when the consumer supplies a
  mapper.
- `watchObjectBoxEntity<E>()` and `ObjectBoxStoreWatchSource` create typed
  Store-level invalidations followed by a consumer-owned authoritative pull.
- `ObjectBoxVersionedProjection` uses consumer key/version/project functions to
  update a `LiveCollection` and reproject only new or changed entities.
- `ObjectBoxProjectionExecutor` borrows the original Store, passes reference
  bytes into `Store.runAsync`, and gives its callback an isolate-local Store
  wrapper.

Transactions and sync:

- `ObjectBoxMutationTransaction` runs a synchronous write transaction:
  `Ok<R>` commits, while typed `Err<F>` or an exception rolls back all writes.
- `ObjectBoxSyncCheckpointStore` performs consumer callback reads/writes/removes
  in ObjectBox transactions and forwards optional fencing tokens unchanged.
- `ObjectBoxSyncRunJournal` appends journal facts and reconstructs immutable
  incomplete-attempt summaries inside borrowed-Store transactions.
- `objectBoxStoreReference` exposes ObjectBox reference bytes for an explicit
  receiving-isolate attachment; no Store object is transferred.

## Ownership and lifecycle

The consumer owns entity annotations, IDs, relations, `objectbox-model.json`,
generated Dart, migrations/model compatibility, Store directory, encryption
keys, codecs, indexes, repository policy, and provider configuration.

Close in this order: reactive builders/consumers, resource sessions,
subscriptions/watchers, queries, projections/background executors, observation
owner, then the original Store. `ObjectBoxStoreOwner` registers its observation
owner after the Store so reverse disposal enforces this order. A borrowed owner
drains its observations but does not close the Store.

For isolate work, send reference bytes, attach a distinct Store wrapper with the
consumer-generated model inside the receiver, close callback-created queries and
graphs in `finally`, and close the isolate-local Store before the original Store.

## Failure, cancellation, and concurrency

Open/configuration failure preserves the primary error and best-effort closes
owned state. Query-source open/read errors become typed failures only with a
consumer mapper; otherwise they remain unexpected errors. Cancellation is
checked around reads, but `Query.findAsync` and native transaction work already
running cannot be force-interrupted; stale publication is suppressed by the
reactive/projection owner.

`ObjectBoxMutationTransaction` callbacks are synchronous because ObjectBox
write transactions are synchronous. Expected `Err` uses rollback and returns
unchanged; unexpected exceptions roll back and rethrow.

`ObjectBoxProjectionExecutor` tracks background work, rejects work after
disposal, and drains before the original Store closes. Only transferable
request/result values are valid. Same-path locking and native concurrency remain
ObjectBox concerns. Checkpoint fencing exists only when the consumer callback
atomically rejects stale tokens.

## Prohibited uses and limitations

- No web support.
- No Store, Box, Query, entity, or generated-model types outside infrastructure.
- No live Store object transferred across isolates.
- No manually edited ObjectBox generated files.
- No asynchronous callback inside `ObjectBoxMutationTransaction`.
- No dual-write or transaction claimed across ObjectBox and another engine.
- No checkpoint/fencing guarantee without consumer schema and atomic comparison.
- No automatic cancellation of a native operation already executing.
- No payloads, entity IDs, paths, query details, or credentials in telemetry.

## Testing

Run `flutter test` for adapter contracts and the native fixture in
`tool/objectbox_native_fixture`. A real generated fixture must cover Store/query/
watcher order, `Query.findAsync`, Store watches, versioned projection,
`Store.runAsync`, isolate attachment/cleanup, domain-plus-outbox commit and
rollback, checkpoints, journals, locking, and zero residual native resources.
Mocks alone do not validate generated-model or native lifecycle compatibility.

## Related packages and guides

Combine with the reactive entrypoint for local-authority observation,
`dartitect_sync` for mutation/outbox and datasets, and
`dartitect_observability` for fixed instrumentation. Read
[adapters](../../docs/guides/adapters.md),
[custom integrations](../../docs/guides/custom-integrations.md), and
[implementation recipes](../../docs/guides/implementation-recipes.md).

## Availability

The workspace contains the `1.0.0-rc.10` source candidate. Supported
Git consumption requires a matching tag and published GitHub Release and the
complete compatible cohort coordinates in its notes. Without one, there is no
supported consumption path. See the
[Git candidate consumption guide](../../docs/guides/git-candidate-consumption.md).
