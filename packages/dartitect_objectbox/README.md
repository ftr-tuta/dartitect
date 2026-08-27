# dartitect_objectbox

[Português (Brasil)](README.pt-BR.md)

## Purpose

Optional ownership and observation lifecycle around a real ObjectBox `Store`.
Entities, model JSON, and generated Dart code remain consumer-owned.

## When to use it

Use it in a native infrastructure composition root after the application has
chosen ObjectBox and generated its model. It is not an ORM abstraction and has
no web support.

## When not to use it

Do not use it for web, before the consumer owns a generated ObjectBox model, or
to hide entities/schema behind a generic ORM abstraction. Never transfer a live
Store across isolates.

## Recommended combinations

Combine with the reactive entrypoint for watcher-backed local authority and
with core mutation contracts for a transactional outbox. Keep transport and
telemetry adapters separate. See the
[ecosystem selection guide](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/ecosystem-selection.md)
and [implementation recipes](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/implementation-recipes.md).

## Install

This candidate is not published on pub.dev. Declare
`dartitect_objectbox: 1.0.0-rc.2` and use the
[Git candidate consumption guide](../../docs/guides/git-candidate-consumption.md)
to generate the complete override closure.

## Minimal example

```dart
final owner = await ObjectBoxStoreOwner.create(openStore: openStore);
try {
  final store = owner.store;
  // Use boxes created from your generated entities/model.
} finally {
  await owner.disposeAsync();
}
```

For reactive reads, pass a consumer-generated builder factory to
`ObjectBoxQuerySource<T, F>` and inject it into a `LiveResource<List<T>, F>`.
The resource borrows the Store, creates one watcher query per hot activation,
and closes that watcher/query when it becomes warm or cold.

`example/` includes a publishable, genuinely generated model and executable.
The repository fixture adds Store/query/watcher, lock, cleanup, and isolate
reference coverage.

## Public API tour

- `ObjectBoxStoreOwner.create`, `.value`, and `.temporary` make ownership clear.
- `ObjectBoxObservationOwner` drains registered queries/watchers before Store.
- `ObjectBoxInstrumentation` wraps open/close operations with minimal tracing.
- `objectBoxStoreReference` produces isolate-transferable reference bytes.
- `ObjectBoxQuerySource` maps watcher invalidations to bounded `LiveResource`
  reads without owning the Store or consumer entities.
- `ObjectBoxVersionedProjection` applies consumer-defined ID/version extractors
  to a `LiveCollection`, reprojecting only new or changed entities.
- `ObjectBoxProjectionExecutor<P, R>` borrows the original Store and delegates
  explicit background work to `Store.runAsync`. The callback receives an
  isolate-local Store wrapper; close callback-created graphs and queries in
  `finally`, then dispose the executor before the original Store.
- `ObjectBoxMutationTransaction` borrows a Store and runs a synchronous write
  callback. Put the consumer's domain and outbox entity writes in that callback;
  `Ok` commits both, while typed `Err` or an exception rolls both back.

## Ownership

The consumer owns entities, schemas, generated files, migrations, encryption
keys, and provider configuration. Close streams/watchers/queries before the
Store. A receiving isolate attaches its own Store and closes it in `finally`.

## Limitations

Web is unsupported. Same-path Store locking and generated-model compatibility
remain ObjectBox concerns. Transaction callbacks must be synchronous. The
helper does not define entities, outbox schemas, conflict policy, or transport.
Background cancellation suppresses publication but cannot interrupt a native
operation already running. Only transferable request/result types are valid.
Never manually edit generated files.

## Extending

Keep repository contracts in the domain and ObjectBox implementations in data.
Reusable integration proposals must include a real generated fixture.

## Testing

Run `flutter test` and the native fixture in `tool/objectbox_native_fixture`.
The fixture verifies `Query.findAsync`, background projection, isolate-local
Store cleanup, real domain/outbox commit and rollback, and watcher teardown; do
not replace it with mocks alone.

## Links

See [adapters](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/adapters.md),
[custom integrations](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/custom-integrations.md), and the [issue tracker](https://github.com/ftr-tuta/dartitect/issues).
