# dartitect_testing

## Purpose

Framework-neutral deterministic clocks, identifiers, schedulers, lifecycle
probes, recording telemetry, stream helpers, and contract harnesses for
Dartitect runtimes. It exports no `package:test` API.

## When to use

Add it as a development dependency when a consumer test needs deterministic
ownership, cancellation, commands, effects, reactive topology, repositories,
model mapping, synchronization, isolates, or observability evidence.

## When not to use

Do not use test helpers as production contracts or replace a real generated/
native provider fixture when SDK compatibility, code generation, transactions,
locking, or teardown are the behavior under test.

## Platforms and entrypoints

Import `package:dartitect_testing/dartitect_testing.dart` from tests. The helpers
are pure Dart and support Dart VM, Flutter, and web subject to the platform of
the production contract under test.

## Mental model and data flow

Tests own every fake and harness. Manual time/IDs remove ambient nondeterminism;
recording observers make sanitized events inspectable. Feature matrices own the
fault controller, observed store, event journal, acknowledgements, graph
registrations, and `ResourceCensus`; fixture drivers can stimulate those
instruments but cannot return self-reported facts or a census map.
Provider-neutral policy uses deterministic helpers, while provider integration
uses an appropriate real or provider-approved fixture.

## Minimal workflow

```dart
import 'package:dartitect_testing/dartitect_testing.dart';

Future<void> main() async {
  final order = <String>[];
  final probe = DisposalProbe(label: 'database', order: order);
  await probe.disposeAsync();
  assert(order.single == 'database:disposeAsync');
}
```

## Public API tour

- `DisposalProbe`, `LifecycleHarness`, `OwnedGraphHarness`,
  `OwnedScopeHarness`, `ResourceCensus`, and census leases verify ownership,
  scope, order, and residual resources.
- `ManualClock`, `ManualScheduler`, `DeterministicIdGenerator`,
  `SequenceSyncIdGenerator`, and `DeterministicTraceIdGenerator` remove time/ID
  randomness.
- `CommandContractHarness` and `EffectContractHarness` exercise terminal command
  and bounded effect contracts.
- `FeatureContractMatrix.online`, `.cache`, `.replica`, and `.offlineFull`
  require profile-specific runtime-driver factories. Every row gets a new
  graph; restart gets a second graph over the same observed durable store.
  Success, expected failure, crash identity, cancellation, concurrency,
  restart, and teardown facts are derived from actual events, revisions,
  acknowledgements, store counters, and the matrix-owned census.
- Host, resilience, jobs, transfer, local-history, restoration, and read-only
  DevTools harnesses cover the stable paved road without provider substitution.
- `RepositoryContractHarness` runs consumer-supplied repository cases.
- `ProjectionContractHarness` and `MapperContractHarness` record selector,
  expected-failure, and bidirectional round-trip evidence.
- `SyncContractHarness`, `CheckpointCrashHarness`, in-memory checkpoint/journal
  stores, and `ManualSyncLeaseStore` cover sync durability and fencing behavior.
- `IsolateWorkerContractHarness` exercises a real isolate protocol.
- `RecordingLogSink`, `RecordingErrorReporter`, `RecordingTracer`, and
  `RecordingSpan` expose observability assertions.
- Privacy policy harnesses and prepared recording destinations exercise the
  local/remote/named profile matrix, destination ownership, isolated queue
  failures, and raw-secret absence. Sentinel helpers reject retained raw values.
- `DiagnosticsTopologyHarness` reconstructs protocol-v2 lifecycle using only
  opaque payload-free events.
- `collectStreamEvents`, `waitForStreamEvent`, `TestingMatrix`, and
  `TestingMatrixAuditor` provide bounded async and coverage utilities.

## Ownership and lifecycle

Each test creates and disposes its own helpers, subscriptions, workers, and
fixtures. Share a manual clock/log only within an explicit test scope. Feature
drivers borrow the matrix-owned harness and must dispose every census lease
they acquire. Contract harnesses borrow the implementation being tested unless
their API documents otherwise. Never turn a fake into global application state.

## Failure, cancellation, and concurrency

Harness results keep expected failure, unexpected crash, cancellation,
admission, cleanup, and residual-resource evidence distinct. Manual scheduling
advances only when the test asks; stream waits are bounded and must be awaited.
Real isolate and synchronization harnesses still require explicit disposal.

A deterministic fake proves policy, not provider thread/process behavior. Use
real fixtures for concurrency, transactions, codegen, locking, and native
resource cleanup.

## Prohibited uses and limitations

- No test runner, matcher library, mocking framework, or production dependency.
- No mock-only claim for generated/native provider compatibility.
- No real network, credentials, DSNs, or remote telemetry in deterministic
  tests.
- No cross-test globals or unbounded waits.
- No substitution of an in-memory transaction for a durability claim.

## Testing

Run `dart test` for this package. Its own suite covers deterministic time/IDs,
harness expected/unexpected paths, cancellation, disposal order, overflow,
isolation, privacy precedence and structural budgets, topology, and zero
residual resources. Consumers should add real
generated Drift/ObjectBox fixtures, a deterministic Dio adapter, and a fake
Sentry Hub as appropriate.

## Related packages and guides

Use the harness matching the production package; keep provider fixtures next to
the provider integration. Read
[implementation recipes](../../docs/guides/implementation-recipes.md),
[custom integrations](../../docs/guides/custom-integrations.md), and
[composition/lifecycle/isolates](../../docs/guides/composition-lifecycle-isolates.md).

## Availability

Dartitect `1.1.0` is distributed only by the annotated `v1.1.0` tag and
its immutable GitHub Release. Declare this package directly with the canonical
Git descriptor; its transitive Dartitect dependencies resolve from the same tag
without overrides. See the
[Git release consumption guide](../../docs/guides/git-release-consumption.md).
