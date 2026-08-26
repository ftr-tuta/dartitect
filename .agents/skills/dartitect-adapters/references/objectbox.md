# ObjectBox adapter

The consumer owns entities, annotations, model JSON, generated Dart code, and
Store configuration. Never edit generated files or treat the adapter as an ORM
abstraction. ObjectBox has no web support.

Create Store/query/watcher resources per native composition root. Close watchers
and queries before the Store. Across isolates, pass supported configuration or
provider references and create isolate-local queries; never send a live Store.
Use the real generated Store/query/watcher fixture, cover same-path locking and
cleanup, and run the supported native-host matrix.
