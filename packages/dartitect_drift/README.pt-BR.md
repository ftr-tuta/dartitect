# dartitect_drift

[English](README.md)

## Objetivo

Adapters explícitos de ciclo de vida, mutação atômica, checkpoint, journal e
tracing do Drift para Dartitect. A aplicação é dona do banco gerado, schema,
migrações, executor, codecs e outbox.

```dart
final owner = await DriftDatabaseOwner.create<AppDatabase>(
  openDatabase: () => AppDatabase(openConsumerExecutor()),
  configure: (database) => database.runConsumerMigrationChecks(),
);
try {
  final transaction = DriftMutationTransaction(owner.database);
  final result = await transaction.run<String, SaveFailure>((database) async {
    await database.saveDomainAndOutbox();
    return const Ok('salvo');
  });
} finally {
  await owner.disposeAsync();
}
```

Use `DriftDatabaseOwner.value` quando outra composição for dona do banco.
Consultas reativas combinam `Selectable.watch()` com o
`StreamReactiveSource` existente; o pacote intencionalmente não cria schema ou
abstração universal de consultas.
