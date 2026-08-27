# dartitect_drift

[Português (Brasil)](README.pt-BR.md)

## Purpose

Explicit Drift lifecycle, atomic mutation, checkpoint, journal, and tracing
adapters for Dartitect. Your application owns its generated database, schema,
migrations, executor, codecs, and outbox.

```dart
final owner = await DriftDatabaseOwner.create<AppDatabase>(
  openDatabase: () => AppDatabase(openConsumerExecutor()),
  configure: (database) => database.runConsumerMigrationChecks(),
);
try {
  final transaction = DriftMutationTransaction(owner.database);
  final result = await transaction.run<String, SaveFailure>((database) async {
    await database.saveDomainAndOutbox();
    return const Ok('saved');
  });
} finally {
  await owner.disposeAsync();
}
```

Use `DriftDatabaseOwner.value` when another composition owns the database.
Adapt reactive queries with Drift's `Selectable.watch()` and Dartitect's
existing `StreamReactiveSource`; this package deliberately adds no schema or
universal query abstraction.
