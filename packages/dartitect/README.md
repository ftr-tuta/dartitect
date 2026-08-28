# dartitect

## Purpose

Pure-Dart primitives for typed expected failures, explicit resource ownership,
cooperative cancellation, bounded command lanes, optional isolate projections,
immutable snapshots, value equality, architecture events, and local diagnostic
protocols. The package has no runtime dependency outside the Dart SDK.

## When to use

Use `dartitect` in domain/application code and composition roots when failure,
ownership, cancellation, or concurrency must be visible in types. It is the
foundation for the other Dartitect runtime packages, but it can be used alone.

## When not to use

Do not add it merely to wrap ordinary values or catch every exception. It does
not provide dependency lookup, UI state, storage, transport, synchronization,
telemetry destinations, or provider configuration.

## Platforms and entrypoints

The public entrypoint is
`package:dartitect/dartitect.dart`. It is pure Dart and supports the Dart VM,
Flutter, and web. Background projection additionally requires an environment
that can spawn isolates and transferable callbacks/values.

## Mental model and data flow

A composition root constructs dependencies and registers only resources it
owns. Application operations return `Result<T, F>` for expected outcomes and
throw for unexpected defects. Cancellation travels down through a
`CancellationSignal`; results and immutable snapshots travel back up. Command
lanes bound admission and publication without becoming application state
containers. Optional observers receive fixed, non-fatal lifecycle facts.

## Minimal workflow

```dart
import 'dart:async';

import 'package:dartitect/dartitect.dart';

Future<Result<int, StateError>> loadCount() async => const Ok<int>(42);

Future<void> main() async {
  final owner = ResourceOwner(label: 'session');
  owner.own(StreamController<void>(), (value) => value.close());
  try {
    switch (await loadCount()) {
      case Ok(:final value):
        print(value);
      case Err(:final failure):
        print('Expected: $failure');
    }
  } finally {
    await owner.disposeAsync();
  }
}
```

## Public API tour

- `Result<T, F>`, `Ok`, `Err`, and `ResultOperations` model exhaustively handled
  expected outcomes.
- `Disposable`, `AsyncDisposable`, `ResourceOwner`, `OwnedGraph`, and
  `OwnedRuntimeSlot` express ownership and generation replacement.
- `CancellationSource`, `CancellationSignal`, and
  `CancellationRegistration` provide cooperative cancellation.
- `CommandLane`, `KeyedCommandLane`, `CommandConcurrency`, and
  `CommandOutcome` provide bounded scheduling with explicit accepted, rejected,
  dropped, cancelled, failed, succeeded, and crash behavior.
- `ProjectionExecutor`, `ProjectionExecution`, and
  `IsolateProjectionExecutor` make inline versus background projection an
  explicit choice.
- `ResourceTransaction` and `ResourceSnapshot` support atomic owned-resource
  changes and immutable local-authority snapshots.
- `BootstrapCoordinator`, named `BootstrapStage` values, and terminal reports
  build an application graph with typed progress, cancellation, deadlines, and
  rollback over the existing transaction primitive.
- `OperationProgress<P>`, `ProgressReporter<P>`,
  `CommandExecutionContext<P>`, and bounded/latest-execution reporters provide
  one execution-fenced typed progress protocol.
- `BoundedLocalHistory<T>` keeps synchronous undo/redo values under count and
  optional weight bounds; it cannot represent callbacks or async effects.
- `IdGenerator`, `SecureUuidV4Generator`, `ValueEquality`, and immutable-copy
  helpers cover small cross-package primitives.
- `ArchitectureObserver` and reactive observer types expose payload-free
  lifecycle facts. `ReactiveJournal` is a bounded memory-only diagnostic ring.
- `DartitectDiagnosticsEmitter`, reporter registrations, subjects, phases, and
  `DartitectDiagnosticBuffer` implement the experimental local diagnostic
  payload-free protocol v2.

## Ownership and lifecycle

The composition root decides whether a dependency is owned or borrowed.
Register only owned resources. `ResourceOwner` disposes in reverse registration
order and aggregates independent failures. Close admission and drain work before
disposing dependencies. `OwnedRuntimeSlot` publishes a complete replacement
generation atomically; a failure while cleaning the old generation does not
make that old generation authoritative again.

Never transfer a live owner, client, database, subscription, or graph across an
isolate. Construct a new graph inside the receiver and transfer validated data.

## Failure, cancellation, and concurrency

`Err<F>` is an expected application result. Unexpected exceptions preserve
their stack and remain crashes. `ResourceCleanupException` reports every cleanup
failure. `OwnedRuntimeReplacementCleanupException` identifies a replacement
that already published even though old cleanup failed.

Cancellation is cooperative: callers can complete promptly while owned work
continues draining. Late results from cancelled, superseded, or disposed work
must not publish. Command policies have positive queue/concurrency bounds;
rejected and dropped calls never start. Isolate projections suppress stale
publication but cannot interrupt arbitrary synchronous work already executing.

## Prohibited uses and limitations

- No service locator, global dependency container, or provider lifecycle.
- No conversion of arbitrary crashes into success or unrelated expected failure.
- No inferred ownership or automatic disposal of borrowed dependencies.
- No exactly-once, persistence, retry, or conflict guarantee.
- No domain payloads, identity, entity keys, or error text in reactive events.
- No automatic background execution.

The diagnostic construction/reporting surface is experimental and has no
remote exporter or global destination by default.

## Testing

Run `dart test`. Cover both `Result` branches, cancellation, every selected lane
policy, busy/disposed admission, stale completion, reverse disposal, aggregated
cleanup failures, observer isolation, and zero residual owned resources.
`dartitect_testing` provides deterministic clocks, IDs, probes, and harnesses.

## Related packages and guides

Use `dartitect_flutter` for Flutter lifecycle and reactive state,
`dartitect_sync` for durable mutations and dataset synchronization,
`dartitect_observability` for telemetry, and `dartitect_testing` for reusable
harnesses. Read the
[getting-started guide](../../docs/guides/getting-started.md),
[commands/results/effects](../../docs/guides/commands-results-effects.md), and
[composition/lifecycle/isolates](../../docs/guides/composition-lifecycle-isolates.md).

## Availability

The workspace contains the `1.0.0-rc.5` source candidate. Supported experimental
Git consumption requires a tag with a corresponding published GitHub Release
and the coordinates from that Release's notes. If no compatible Release exists,
there is no supported consumption path; see the
[experimental consumption guide](../../docs/guides/git-candidate-consumption.md).
