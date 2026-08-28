# ObjectBox adapter

The consumer owns entities, annotations, model JSON, generated Dart code, and
Store configuration. Never edit generated files or treat the adapter as an ORM
abstraction. ObjectBox has no web support.

Use `ObjectBoxStoreOwner.create` for an owned Store and `.value` for a borrowed
one. `ObjectBoxQuerySource` owns one query watcher and its queries per hot
activation; `ObjectBoxStoreWatchSource` owns typed Store-watch subscriptions
and delegates the authoritative pull. Versioned projections borrow the Store
and collection. `ObjectBoxProjectionExecutor` uses `Store.runAsync`; dispose it
before the original Store.

Keep domain and outbox writes in one synchronous
`ObjectBoxMutationTransaction`. Checkpoint and journal adapters borrow the Store
and delegate entities, codecs, and fencing comparison to consumer callbacks.
Across isolates, send `objectBoxStoreReference` bytes, attach an isolate-local
Store with the generated model, and close it in `finally`; never send a live
Store. Close resource sessions, watchers, queries, projection executors, and
observation owners before the Store. Use a real generated fixture for locking,
transaction, async projection, isolate attachment, and teardown evidence.
