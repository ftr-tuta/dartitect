# Drift adapter

The consumer owns the `GeneratedDatabase`, tables, DAOs, migrations, codecs,
executor, database path, and web assets/storage policy. `dartitect_drift`
provides lifecycle, transaction, checkpoint, journal, and sanitized tracing
around those injected choices; it is not an ORM or universal database layer.

Use a consumer conditional export with a stub, `dart.library.ffi` for native,
and `dart.library.js_interop` for web. Native may use
`NativeDatabase.createInBackground`; web uses app-owned `WasmDatabase.open`, a
compatible worker and `sqlite3.wasm`, correct MIME/COOP/COEP policy, and a
multi-context-safe storage implementation. Reject unsafe IndexedDB/in-memory
for multi-context durability.

Use `DriftDatabaseOwner.create` only when the composition root owns the
database; use `.value` for borrowed databases. Keep domain and outbox writes in
one `DriftMutationTransaction`. Pass fencing tokens unchanged to consumer-owned
checkpoint callbacks. Adapt `Selectable.watch()` with `StreamReactiveSource`.
Dispose observations, sync, and repositories before the database.
