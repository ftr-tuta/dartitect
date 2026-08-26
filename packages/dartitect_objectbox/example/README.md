# ObjectBox example

This publishable example retains a genuinely generated consumer model:
`fixture_entity.dart`, `objectbox-model.json`, and `objectbox.g.dart`. Run it on
a native host with ObjectBox libraries available:

```console
dart run example/dartitect_objectbox_example.dart
```

The executable opens a temporary Store through `ObjectBoxStoreOwner`, writes
and reads one generated entity, then closes the Store and removes the owned
directory. The repository's larger
[`tool/objectbox_native_fixture`](../../../tool/objectbox_native_fixture/)
also covers queries, watchers, same-path locking, cleanup, and isolate
references.

Generated files are intentionally retained. Consumer entities, schemas,
migrations, encryption keys, and provider configuration remain consumer-owned.
