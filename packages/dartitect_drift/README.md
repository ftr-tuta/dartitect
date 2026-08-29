# dartitect_drift

## Purpose

Explicit lifecycle, typed transaction rollback, checkpoint, journal, and
sanitized instrumentation adapters around a consumer-generated Drift database.
The package does not define a database, table, migration, executor, or query
abstraction.

Config-v2 generation exposes one `<Context>DartitectDriftFragment` whose
operational `tables` are explicitly included by the consumer-owned database.
The fragment versions only SDK-owned operational tables; domain migrations
remain consumer-owned.

## When to use

Use it after an application has selected Drift and owns a generated
`GeneratedDatabase`. It is useful when database ownership must be explicit,
domain and outbox writes must share one transaction, or `dartitect_sync` needs
checkpoint/journal adapters over consumer tables.

## When not to use

Do not add it before selecting Drift, expose it through domain/ViewModel APIs,
or expect it to generate schema and migrations. Do not use it to coordinate a
transaction across Drift and another persistence engine.

## Platforms and entrypoints

Import `package:dartitect_drift/dartitect_drift.dart`. The adapter follows the
platforms supported by the consumer's Drift executor: Dart VM and native Flutter
with an appropriate native executor, and web with an appropriate web executor.
Executor selection and worker setup remain consumer-owned.

## Mental model and data flow

A composition root creates or receives a generated database and wraps it in
`DriftDatabaseOwner`. Repositories borrow `owner.database`. Writes that must
commit together run through `DriftMutationTransaction`; an expected `Err` forces
rollback and is returned unchanged. Reactive reads remain ordinary Drift
`Selectable.watch()` streams adapted by
`StreamReactiveSource` from `dartitect_flutter`.

Checkpoint and journal adapters borrow the same generated database and delegate
serialization/query details to consumer callbacks. Instrumentation wraps only
fixed operations and cannot see SQL, bound values, table names, entities, or
credentials.

## Minimal workflow

```dart
import 'package:dartitect/dartitect.dart';
import 'package:dartitect_drift/dartitect_drift.dart';
import 'package:drift/drift.dart';

Future<Result<String, SaveFailure>>
saveDomainAndOutbox<AppDatabase extends GeneratedDatabase>(
  AppDatabase database,
  Future<void> Function(AppDatabase database) writeBoth,
) {
  return DriftMutationTransaction<AppDatabase>(database)
      .run<String, SaveFailure>((borrowed) async {
        await writeBoth(borrowed);
        return const Ok<String>('saved');
      });
}

final class SaveFailure implements Exception {
  const SaveFailure();
}
```

At composition, use `DriftDatabaseOwner.create` when this graph opens and closes
the database:

```dart
final owner = await DriftDatabaseOwner.create<AppDatabase>(
  openDatabase: () => AppDatabase(openConsumerExecutor()),
  configure: (database) => database.runConsumerMigrationChecks(),
);
```

Use `DriftDatabaseOwner.value(existingDatabase)` when another owner closes it.

## Public API tour

- `OpenDriftDatabase` and `DriftDatabaseOwner.create` open, configure, guard,
  and close a consumer-generated database. `DriftDatabaseOwner.value` borrows
  one and never closes it.
- `DriftMutationTransaction` borrows the database. `Ok<R>` commits; typed
  `Err<F>` rolls back every write and is returned unchanged; unexpected
  exceptions roll back and retain their stack.
- `DriftSyncCheckpointStore` implements `SyncCheckpointStore` through
  consumer-owned read/write/remove callbacks. The write callback receives the
  fencing token unchanged.
- `DriftSyncRunJournal` appends `SyncJournalEntry` values and reconstructs
  immutable `IncompleteSyncAttempt` lists through consumer callbacks.
- `DriftInstrumentation` and `DriftInstrumentedOperation` wrap fixed
  open/close/transaction/checkpoint/journal boundaries with borrowed
  observability contracts.

There is intentionally no reactive-query wrapper. Compose a consumer query with
`StreamReactiveSource` so the activation-local stream subscription belongs to
the resource while the database remains borrowed.

## Ownership and lifecycle

The consumer owns the generated database class, table definitions, schema
version, migrations, executor, isolate/web worker configuration, codecs,
encryption, query semantics, indexes, outbox/checkpoint/journal tables, and
retention.

`.create` owns the database and closes it; `.value` guards access but borrows the
database. Dispose reactive resource sessions, stream subscriptions, repository
graphs, checkpoint/journal users, and transaction producers before disposing an
owned database. The adapters themselves never close a borrowed database.

## Failure, cancellation, and concurrency

Opening/configuration failures preserve the primary error and best-effort close
an already opened owned database. Access after disposal throws `StateError`.
`ResourceOwner` semantics apply to database close failures.

A typed `Err` inside `DriftMutationTransaction` triggers rollback by an internal
sentinel and is returned with its original failure/stack. An unexpected
exception also rolls back through Drift and is rethrown with its original stack.

Checkpoint operations check cancellation before starting; reads also check after
completion. Database transactions already running are governed by Drift and
cannot be preempted by cooperative cancellation. Concurrent read/write and
isolate behavior follow the consumer-selected Drift executor. The consumer must
atomically compare a fencing token in the same transaction as the dataset
commit when fencing matters.

## Prohibited uses and limitations

- No global database or service-location access.
- No schema, migration, executor, codec, entity, or SQL ownership by Dartitect.
- No provider types in domain, application, ViewModel, or presentation APIs.
- No dual-write or claimed cross-engine transaction.
- No checkpoint advance before local coverage commits.
- No claim that receiving a fencing token enforces fencing without an atomic
  consumer comparison.
- No SQL text, table/column names, parameters, rows, payloads, or credentials in
  instrumentation.

## Testing

Run `dart test`. Use a real generated test database to cover owned and borrowed
close behavior, failed configuration cleanup, domain-plus-outbox commit,
typed/unexpected rollback, post-commit watchers, checkpoint fencing callbacks,
journal reconstruction/immutability, cancellation boundaries, and sanitized
instrumentation. Run native and web fixtures for the executors the application
supports.

## Related packages and guides

Combine with `dartitect_sync` for mutation/outbox and dataset orchestration,
`dartitect_flutter` for `StreamReactiveSource`, and
`dartitect_observability` for instrumentation. Read
[adapters](../../docs/guides/adapters.md),
[custom integrations](../../docs/guides/custom-integrations.md), and
[implementation recipes](../../docs/guides/implementation-recipes.md).

## Availability

The workspace contains the `1.0.0-rc.6` source candidate. Supported
Git consumption requires a matching tag and published GitHub Release and uses
the complete cohort coordinates from its notes. If none exists, there is no
supported consumption path. See the
[Git candidate consumption guide](../../docs/guides/git-candidate-consumption.md).
