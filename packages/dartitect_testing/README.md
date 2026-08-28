# dartitect_testing

[Português (Brasil)](README.pt-BR.md)

## Purpose

Framework-neutral probes, manual time, lifecycle helpers, stream waits,
recording telemetry, and repository contract harnesses. It exports no
`package:test` type.

## When to use it

Use it in consumer tests that need deterministic Dartitect boundary behavior.
It does not prescribe a test runner or mock framework.

## When not to use it

Do not replace a real generated/provider fixture when SDK compatibility,
codegen, transactions, or native lifecycle are the behavior under test. It does
not define production contracts.

## Recommended combinations

Combine with whichever runtime, reactive, offline-first, observability, adapter,
or tooling boundary the test verifies. Use deterministic fakes for policy and a
real fixture for integration. See the
[ecosystem selection guide](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/ecosystem-selection.md)
and [implementation recipes](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/implementation-recipes.md).

## Install

This candidate is not published on pub.dev. Declare
`dartitect_testing: 1.0.0-rc.3` under `dev_dependencies` and use the
[Git candidate consumption guide](../../docs/guides/git-candidate-consumption.md)
to generate the complete override closure.

## Minimal example

```dart
final order = <String>[];
final probe = DisposalProbe(label: 'database', order: order);
await probe.disposeAsync();
assert(order.single == 'database:disposeAsync');
```

## Public API tour

- `DisposalProbe` and `LifecycleHarness` expose order and cleanup failures.
- `ManualClock` and `DeterministicTraceIdGenerator` remove time/ID randomness.
- recording sinks/reporters/tracers/spans expose telemetry assertions.
- `RepositoryContractHarness` runs reusable repository contract cases.
- `ProjectionContractHarness` records deterministic generated-selector evidence.
- `MapperContractHarness` records forward results and bidirectional round trips.
- `collectStreamEvents` and `waitForStreamEvent` bound async stream tests.
- `DiagnosticsTopologyHarness` reconstructs protocol-v1 topology, generation,
  revision, and terminal lifecycle using only opaque payload-free events.

## Ownership

Fakes are created and disposed by each test. Share explicit logs/clocks only
within a test scope; do not turn helpers into global application state.

## Limitations

Real provider boundaries still need real or provider-approved fixtures. Use a
generated ObjectBox model, mock Dio adapter, and fake Sentry Hub with no network.

## Extending

Add consumer-owned fakes next to the contract they implement. Keep this package
free of a test-runner API.

## Testing

Run `dart test`; cover expected/unexpected failure, cancellation, retry,
disposal order, overflow, isolation, and zero residual resources.

## Links

See [testing guidance](https://github.com/ftr-tuta/dartitect/blob/main/.agents/skills/dartitect-testing/references/test-matrix.md),
[custom integrations](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/custom-integrations.md), and the [issue tracker](https://github.com/ftr-tuta/dartitect/issues).
