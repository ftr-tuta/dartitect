# Transfer and Workmanager adapters

`dartitect_transfer` owns provider-neutral chunk planning, checksums, progress,
and checkpoints. Remote protocol, Range/ETag semantics, authentication,
idempotency, retry classification, picker/share/gallery ports, and durable
metadata/outbox transactions remain consumer-owned. A checkpoint advances only
after the chunk commit is durable. Use `dartitect_dio` only as the selected
transport adapter and never retry an uncertain mutation implicitly.

`dartitect_workmanager` adapts a consumer-initialized Workmanager callback to a
versioned `JobDispatcher`. Build a fresh graph per accepted execution, validate
the envelope, preserve deadline/cancellation/receipt semantics, and close the
graph in `finally`. The consumer owns registration, recurrence, platform policy,
constraints, and provider lifecycle. Test Android/iOS/macOS through supported
plugin boundaries, preserve preview limitations on web/Linux, and return typed
unsupported on Windows.
