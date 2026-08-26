# dartitect

[Português (Brasil)](README.pt-BR.md)

## Purpose

Pure-Dart primitives for typed expected failures, deterministic lifecycle
ownership, and optional architecture events. The package has no runtime
dependencies outside the Dart SDK.

## When to use it

Use it at domain/application boundaries and composition roots. It is useful
when resource lifetime and expected failure must be visible in types. It is not
a dependency-injection container, service locator, state manager, or logger.

## When not to use it

Do not add it merely to wrap ordinary values or exceptions without a typed
recovery contract. It does not supply UI, storage, transport, telemetry, or a
runtime container.

## Recommended combinations

Combine with `dartitect_flutter` only at Flutter presentation, with
`dartitect_observability` for neutral telemetry contracts, and with provider
adapters only at infrastructure composition. See the
[ecosystem selection guide](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/ecosystem-selection.md)
and [implementation recipes](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/implementation-recipes.md).

## Install

This candidate is not published on pub.dev. Declare
`dartitect: 1.0.0-rc.1` and follow the
[Git candidate consumption guide](../../docs/guides/git-candidate-consumption.md)
to pin the package and its transitive Dartitect dependencies to the protected
tag.

## Minimal example

```dart
import 'package:dartitect/dartitect.dart';

Future<Result<int, String>> loadCount() async => const Ok(3);

Future<void> main() async {
  final owner = ResourceOwner(label: 'session')
    ..own(_Connection(), (value) => value.dispose());
  final result = await loadCount();
  switch (result) {
    case Ok(:final value): print(value);
    case Err(:final failure): print('Expected: $failure');
  }
  await owner.disposeAsync();
}

final class _Connection {
  void dispose() {}
}
```

## Public API tour

- `Result<T, F>`, `Ok`, `Err`, and `ResultOperations` model expected outcomes.
- `Disposable` and `AsyncDisposable` define narrow lifecycle contracts.
- `ResourceOwner` disposes owned resources in reverse registration order and
  reports all cleanup failures through `ResourceCleanupException`.
- `ArchitectureObserver`, `ArchitectureEvent`, and
  `NoOpArchitectureObserver` expose optional, non-fatal architecture signals.
- `CancellationSource`/`CancellationSignal`, `CommandLane`, and
  `KeyedCommandLane` provide typed, bounded scheduling without Flutter.
- `ProjectionExecution` keeps projection inline by default.
  `IsolateProjectionExecutor<P, R>` is an explicit per-task background option
  for transferable requests/results; cancellation suppresses stale results and
  disposal drains workers so isolate-local `finally` cleanup can finish.
- `MutationCommand<A, K, T, F>` runs local-first mutations in bounded
  per-key sequential lanes. `MutationOutboxStore` keeps the atomic local
  change/outbox transaction consumer-owned; `OutboxOperation` preserves one
  idempotency key across at-least-once delivery and session recovery.
- `CommitDisposition`, `EntitySyncState`, `MutationFailurePolicy`, and
  `RetryClassification` distinguish queued, rejected, conflicted, and uncertain
  outcomes. Automatic retry is opt-in and bounded; compensation and crash-lane
  resume are explicit.
- `ChangeCause`, `ReactiveChangeEvent`, and `ReactiveObserver` expose only
  registered static causes, revisions, duration, and listener counts.
  `ReactiveJournal` is an opt-in, memory-only ring with a default capacity of
  200; `SafeReactiveObserver` isolates and disables a failing destination.

## Ownership

The composition root decides whether a value is owned or borrowed. Register
only owned values with `ResourceOwner`; dispose dependents before dependencies.
Never transfer live owned resources across isolates.

## Limitations

`Result` does not convert unexpected exceptions into success or expected
failure. `ResourceOwner` cannot infer ownership and does not replace provider
lifecycle rules. `MutationCommand` cannot make a non-transactional repository
atomic or promise exactly-once delivery; the consumer schema and transport must
enforce their documented idempotency scope. Reactive events deliberately carry
no domain payload, operation key, error text, identity, or persisted history.
Background execution is never selected automatically and requires a platform
with isolate spawning plus transferable callbacks and values.

## Extending

Implement the small public contracts directly. Keep provider SDKs and business
types in the consuming application or an isolated adapter package.

## Testing

Run `dart test`. Cover atomic local/enqueue rollback, offline queueing,
at-least-once duplicates, crash/audit recovery, and explicit compensation.
`dartitect_testing` adds deterministic probes and contract harnesses without
re-exporting a test runner.

## Links

See the [workspace guide](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/getting-started.md),
[API policy](https://github.com/ftr-tuta/dartitect/blob/main/VERSIONING.adoc), and [issue tracker](https://github.com/ftr-tuta/dartitect/issues).
