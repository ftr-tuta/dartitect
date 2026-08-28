# dartitect_transfer

`dartitect_transfer` copies bounded chunks from a provider-neutral source to a
transport. It supports durable checkpoints, checksums, typed progress,
pause/resume, cancellation, and deadlines. A checkpoint is saved only after
the transport acknowledges durable commit of the complete chunk.

The package does not define authentication, URLs, ETag or Range policy,
idempotency semantics, or a universal remote protocol. Applications configure
those details in their source and transport adapters.

```dart
final engine = TransferEngine<MyFailure>(
  source: source,
  transport: transport,
  checkpoints: checkpointStore,
);
final result = await engine.start('avatar-upload').done;
```
