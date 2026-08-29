# Drift composition-root recipe

`dartitect create app --adapters=drift` adds only the `dartitect_drift`
dependency and this recipe. The application owns its Drift schema, migrations,
executor, codecs, database file or web assets, and generated code.

1. Put the consumer `GeneratedDatabase`, tables, and DAOs under the feature's
   `infrastructure/` directory. Keep them out of domain, application, and
   presentation.
2. Select the executor in consumer code with conditional exports: a stub, then
   `dart.library.ffi` for native and `dart.library.js_interop` for web. Configure
   `NativeDatabase.createInBackground` or `WasmDatabase.open` there.
3. At an app, session, route, or isolate composition root, open the database
   through `DriftDatabaseOwner.create(openDatabase: ...)`. Inject repositories,
   `DriftMutationTransaction`, `DriftSyncCheckpointStore`, and
   `DriftSyncRunJournal`; do not expose Drift types through feature contracts.
4. Adapt a consumer `Selectable.watch()` stream through Dartitect's existing
   `StreamReactiveSource`. Dispose observations, sync, and repositories before
   the database owner.

When Drift and ObjectBox coexist, assign different bounded contexts and a
single writer per dataset or partition. Do not dual-write, bridge schemas, or
attempt a transaction across engines.
