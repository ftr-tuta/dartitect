# Dartitect Isolates

[Português (Brasil)](README.pt-BR.md)

## Purpose

Typed, generation-scoped isolate workers with explicit readiness, correlated
ACKs, heartbeats, request deadlines, crash/exit handling, and safe-stop.

Protocol version 2 separates the caller-facing request ID from a monotonic,
generation-local wire correlation nonce. A public ID may be reused only after
its request is terminal; a late envelope for the old nonce is discarded and
cannot complete the new request. `accepted` and `result` may be awaited
independently without creating an unobserved sibling-Future error.

## When to use

Use `IsolateWorker<P, R, F>` when a native Dart or Flutter workload needs one
owned worker and a bounded typed protocol. The handler returns `Result<R, F>`
for expected failures; unexpected remote crashes retain their remote stack.

## Ownership

The caller owns the worker supervisor. Each receiver builds its own graph. Only
validated transferable values cross the boundary; clients, Stores, ViewModels,
subscriptions, timers, and owners never do. Call `safeStop()` during reverse
teardown; forced termination is only the deadline fallback.

Payloads, expected failures, and successful results are copied according to
Dart isolate transfer rules. Validate a versioned DTO at the boundary; do not
use this protocol as a serialization framework or hide copy cost.

## Testing

Use the real-isolate contract harness in `dartitect_testing` to exercise ACK,
result/failure, deadline, crash, and zero residual requests. Run `dart test` for
the package protocol suite.

## Limitations

This package is not a scheduler, process manager, global worker registry,
serialization framework, or infinite restart policy. Web is not declared until
an equivalent tested contract exists.
