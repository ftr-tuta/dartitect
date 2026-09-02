# dartitect_isolates

## Purpose

Typed, generation-scoped isolate workers with explicit readiness, correlated
acceptance, heartbeats, per-request deadlines, crash/exit handling, and
cooperative safe stop.

## When to use

Use `IsolateWorker<P, R, F>` for a native Dart or Flutter workload that benefits
from one long-lived owned worker and a bounded typed request protocol. Use
`IsolateWorkerPool<P, R, F>` when a fixed number of workers should share bounded
in-flight and queued admission.

## When not to use

Do not use it as a process manager, global worker registry, serialization
framework, infinite restart policy, or a way to pass provider resources between
isolates. Small or rare work may be clearer inline or through an explicit
per-task projection executor.

## Platforms and entrypoints

Import `package:dartitect_isolates/dartitect_isolates.dart`. It supports Dart VM
and native Flutter platforms with isolate spawning. Web is not supported.

## Mental model and data flow

The caller owns a supervisor. `IsolateWorker.spawn` creates one generation,
waits for protocol readiness, and sends versioned envelopes containing
transferable request data. The receiver executes an `IsolateRequestHandler` in
its own isolate-local graph and returns `Result<R, F>`. Protocol version 2 keeps
a public request ID separate from a monotonic generation-local wire nonce, so a
late response cannot complete a later reuse of the same public ID.

## Minimal workflow

```dart
import 'package:dartitect/dartitect.dart';
import 'package:dartitect_isolates/dartitect_isolates.dart';

Future<void> main() async {
  final worker = await IsolateWorker.spawn<int, int, StateError>(
    handler: _double,
  );
  try {
    final result = await worker.execute(21, requestId: 'double-21');
    assert(result == const Ok<int>(42));
  } finally {
    await worker.safeStop();
  }
}

Future<Result<int, StateError>> _double(
  int value,
  CancellationSignal cancellation,
) async {
  cancellation.throwIfCancelled();
  return Ok<int>(value * 2);
}
```

## Public API tour

- `IsolateWorker.spawn`, `send`, `execute`, and `safeStop` own the worker
  lifecycle and request flow; `send` and `execute` accept optional cooperative
  cancellation.
- `IsolateWorkerPool.spawn`, `execute`, `mapSequence`, and `disposeAsync`
  provide FIFO bounded admission, optional result-order preservation, draining
  shutdown, and explicit fail-pool or finite replacement crash policy.
- `IsolateRequestReceipt` exposes acceptance and result futures independently.
- `IsolateRequestHandler` is the receiver callback contract.
- `IsolateWorkerException`, readiness, heartbeat, deadline, unexpected-exit,
  and `RemoteIsolateCrash` types distinguish terminal failures.
- `currentIsolateWorkerProtocolVersion` identifies the wire contract.

## Ownership and lifecycle

The caller owns the worker and calls `safeStop()` during reverse teardown. The
receiver builds and disposes its own clients, databases, subscriptions, and
other resources. Only versioned transferable DTOs and expected failure/result
values cross the port boundary. Forced termination is a deadline fallback after
cooperative stop has been requested.

## Failure, cancellation, and concurrency

Expected handler failures use `Err<F>`. Unexpected remote exceptions become
`RemoteIsolateCrash` with the remote stack; readiness, heartbeat, deadline, and
unexpected exits remain distinct failures. Acceptance and result can be awaited
separately without an unobserved sibling-future error.

Cancellation is cooperative. A timed-out request becomes terminal locally and
late envelopes for its old nonce are discarded. Public request IDs cannot be
reused while active. Requests share the owned worker, while nonce correlation
prevents cross-request publication.

## Prohibited uses and limitations

Never transfer clients, Stores, databases, owners, ViewModels, subscriptions, or
closures that capture live resources. Validate protocol version and DTO shape
before provider work. Dart isolate copying and transfer costs still apply.
There is no web contract or automatic restart loop.
The pool does not replay a request whose effect is uncertain after a crash and
does not materialize `TransferableTypedData` on the caller's behalf.

## Testing

Run `dart test`. Use the real-isolate harness in `dartitect_testing` to cover
readiness, acceptance, success, expected failure, crash, heartbeat, deadline,
late envelopes, reused public IDs, safe stop, and zero residual requests.

## Related packages and guides

Use the core `IsolateProjectionExecutor` for explicit per-task projection and
`dartitect_sync` for versioned headless sync commands. Read
[composition/lifecycle/isolates](../../docs/guides/composition-lifecycle-isolates.md)
and [offline-first recipes](../../docs/guides/implementation-recipes.md). The
[incremental operations guide](../../docs/guides/incremental-operations.md) and
[worker-pool example](example/isolate_worker_pool_example.dart) cover bounded
pool admission and ordered mapping.

## Availability

Dartitect `1.0.0` is distributed only by the annotated `v1.0.0` tag and
its immutable GitHub Release. Declare this package directly with the canonical
Git descriptor; its transitive Dartitect dependencies resolve from the same tag
without overrides. See the
[Git release consumption guide](../../docs/guides/git-release-consumption.md).
