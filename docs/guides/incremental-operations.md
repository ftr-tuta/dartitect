# Incremental operations

The stable `1.1.0` / `v1.1.0` cohort contains the opt-in incremental APIs
described here. Applications on `1.0.0` must upgrade the complete lockstep
cohort before importing these entrypoints.

## Choose incremental execution deliberately

Use incremental execution when the consumer benefits from the first item or a
partial aggregate before the complete input is available, and when input,
retention, cancellation, and cleanup need explicit bounds. Keep the one-shot
command or `SyncDataset` constructor when the result is inherently atomic and
partial progress has no consumer meaning.

Incremental operations do not select batching, retries, persistence, conflict
resolution, provider concurrency, or product progress. Those remain consumer
policy. The new API adds two opt-in entrypoints to the existing 25 packages:

- `package:dartitect/dartitect_incremental.dart` for pure Dart execution;
- `package:dartitect_flutter/dartitect_flutter_incremental.dart` for a
  Material-neutral Flutter command projection.

## Run a cold core operation

Create a fresh source for each execution. Use `IncrementalOperation.sync` only
for finite resource-free iterables, `syncCloseable` for an owned synchronous
source, and `async` for a cold single-subscription stream.

```dart
final operation = IncrementalOperation<int, LoadFailure>.async(() async* {
  for (var value = 1; value <= 1000; value++) {
    yield Ok<int>(value);
  }
});

final folded = await operation.fold<int>(
  initial: 0,
  reducer: (sum, value, context) => sum + value,
);
```

The factory is called again on every run. Sequence numbers start at one, the
clock is UTC and injectable, and each successful item has unit weight unless a
`weightOf` callback is supplied. Defaults allow at most 100,000 emissions and
100,000 cumulative weight units. The item that would cross either limit never
reaches the consumer.

`consume` retains no items. `fold` retains only the explicit aggregate.
`collectBounded` retains the latest items up to its capacity and reports how
many were dropped. Use `BoundedRingBuffer<T>` directly only when bounded recent
history is part of the consumer contract.

See the complete [core example](../../packages/dartitect/example/incremental_operation_example.dart).

## Preserve backpressure, stacks, and cleanup

The runtime awaits `onValue` before requesting another item. It rejects a
broadcast stream, stops at the first `Err`, and never invents a retry. Producer,
stream, reducer, consumer, and cleanup errors preserve their original stack.

Cancellation or a UTC deadline stops admission, cancels and awaits the stream
subscription, lets an `async*` producer finish its `finally`, and only then
publishes the terminal result. Synchronous CPU work cannot be preempted, so keep
work between emissions bounded. Dart's `Iterator` has no close protocol; use an
explicit closeable source for owned file, cursor, or provider resources. These
constraints follow Dart's [cold stream and cancellation model](https://dart.dev/libraries/async/creating-streams).

## Project partial state into Flutter

`IncrementalCommand<Item, Aggregate, Failure, Progress>` creates a fresh initial
aggregate per execution and reuses `CommandConcurrency`, including
`restartLatest`. Every admitted item passes through the reducer. Choose only the
notification cadence:

- `everyEmission` publishes every running update;
- `coalesceMicrotask` combines updates that occur before its scheduled
  microtask runs;
- `coalesceFrame` combines running updates behind the injected frame scheduler.

Idle, running, succeeded, failed, cancelled, and crashed states are sealed and
retain the partial aggregate, emission count, weight, execution ID, latest
progress, and payload-free receipt as applicable. Terminal publication fences
pending frame/microtask callbacks. `IncrementalCommandStateBuilder` borrows the
command, accepts a static child, pauses under disabled `TickerMode`, and adds no
Material, text, layout, navigation, or styling.

See the [Flutter example](../../packages/dartitect_flutter/example/incremental_command_example.dart).

## Confirm incremental datasets

`SyncDataset.incremental` returns an incremental operation whose successful
items are `SyncDatasetOutcome` values. The engine validates cancellation,
deadline, and lease authority, serializes checkpoint persistence, and confirms
the checkpoint before pulling another item. The first typed failure stops that
dataset; a checkpoint failure after consumer application marks the boundary
incomplete.

`SyncExecutionPolicy.sequential()` remains the default. With
`boundedParallel(maxConcurrent)`, the engine admits ready nodes in declared plan
order, runs only dependency-independent nodes, continues unrelated branches
after a typed failure, blocks descendants, and drains admitted work after an
unexpected crash. Reports retain declared topological order. Checkpoint, lease,
journal, and cleanup ports remain single-flight because borrowed ports are not
assumed concurrent.

`SyncRun.checkpointProgress` is additive and reports confirmed step counts
without changing the exhaustive `SyncProgressPhase` enum. See the
[incremental sync example](../../packages/dartitect_sync/example/incremental_sync_example.dart).

## Bound native isolate work

`IsolateWorkerPool.spawn` creates a fixed number of VM/native Flutter workers
with explicit `maxInFlight` and `maxQueued` bounds. `execute` admits one request.
`mapSequence` pauses input at capacity and can preserve input order or emit
completion order. Ordered mode also bounds completed results waiting for an
earlier request.

The default `failPool` crash policy makes the pool terminal. The opt-in
`replaceWorker(maxReplacements)` spends a finite replacement budget and never
replays the request whose effect is uncertain. `disposeAsync` closes admission,
drains admitted work, then safe-stops every worker. Web has no silent main-isolate
fallback; use core incremental operations or a consumer-provided worker.

Pass `TransferableTypedData` through without materializing it in the pool. Dart
transfers ownership in constant time after construction, as described by the
[Dart API](https://api.dart.dev/dart-isolate/TransferableTypedData-class.html).
See the [worker-pool example](../../packages/dartitect_isolates/example/isolate_worker_pool_example.dart).

## Inspect progressive tooling

`ProjectScanner.scanEvents()` emits sealed started, file-discovered,
file-analyzed, finding, completed, or cancelled events. Discovery and terminal
order are deterministic while at most four files are analyzed concurrently.
`ProjectSourceIndex` retains at most 2,048 immutable fact records keyed by
content and configuration; it never retains source or ASTs.

Use the compatibility collector for ordinary scans or stream JSON Lines:

```console
dartitect scan --jsonl
dartitect inspect execution-model --json
```

`--jsonl` is mutually exclusive with JSON and SARIF. SIGINT emits a cancelled
event and exits 130. The execution-model inspector reports DT2200-DT2211 and is
non-blocking except for usage or internal errors. MCP sends only analyzed and
total counts when the request supplies a progress token; it never places source,
finding text, or paths in progress notifications. See the
[progressive scanner example](../../packages/dartitect_cli/example/progressive_scan_example.dart).

## Measure portable invariants first

The curated benchmark contract covers 0, 1, 32, 1,000, and 100,000 emissions;
eager inputs, sync/async generators, batches, slow consumers, cancellation,
Flutter, sync, isolates, observability fan-out, and CLI scans. Bounds,
backpressure, cleanup, stable order, single-flight ports, one classification per
node, deterministic events, and zero residual work are blocking. First-item
latency, total time, RSS, p50, and p95 are informative and comparable only on
the same runner.

Run:

```console
dart run tool/check_incremental_benchmark.dart
dart run tool/verify.dart --skip-get
```

Record the SDK, OS, architecture, execution mode, warmup, repetitions, input,
and bounds with any timing claim. Do not weaken cleanup, privacy, ordering, or
backpressure to improve a number.
