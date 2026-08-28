# dartitect_transfer

## Purpose

Provider-neutral contracts for bounded resumable chunk transfer with durable
checkpoints, optional checksums, typed progress, pause/resume, cancellation, and
deadlines.

## When to use

Use it when a consumer-defined source and destination need a reviewable local
or remote chunk orchestration contract with durable resume evidence.

## When not to use

Do not use it as a universal upload/download protocol. It does not define URLs,
auth, ETag, Range, remote idempotency, object storage, or payload logging.

## Platforms and entrypoints

Import `package:dartitect_transfer/dartitect_transfer.dart`. It is pure Dart and
supports the Dart VM, Flutter, and web, subject to the selected adapters.

## Mental model and data flow

`TransferSource` yields a bounded chunk from an approved offset. The transport
reports its durable exclusive offset. Only then does the engine persist a new
checkpoint revision and publish committed progress.

## Minimal workflow

```dart
final engine = TransferEngine<MyFailure>(
  source: source,
  transport: transport,
  checkpoints: checkpointStore,
);
final result = await engine.start('avatar-upload').done;
```

## Public API tour

`TransferChunk`, checksums, checkpoints, source, sink, and transport types define
the boundary. `TransferEngine` and `TransferRun` implement serialized execution,
pause/resume/cancel, deadlines, progress, and a terminal `TransferReport`.

## Ownership and lifecycle

The composition root owns the engine and disposes it before source, transport,
checkpoint storage, or provider resources. Those ports are borrowed. Disposal
cancels and drains an active run and clears control references.

## Failure, cancellation, and concurrency

Expected transport failures remain `Result` values. Protocol/checksum invariant
failures and unexpected exceptions escape. Pause blocks the next boundary;
cancellation wakes paused work. One engine admits one transfer at a time.

## Prohibited uses and limitations

- Never checkpoint before durable destination acknowledgement.
- Never log chunk bytes, URL, headers, credentials, or remote payloads.
- Never infer exactly-once delivery or remote resume policy.
- Never reuse one engine for unbounded concurrent transfers.

## Testing

Run `dart test`. Cover chunk order, post-commit checkpoints, resume, checksums,
pause/resume/cancel, deadline, expected failure, protocol crash, progress, and
disposal. Test provider adapters at their real SDK boundary.

## Related packages and guides

Use `DioTransferTransport` from `dartitect_dio` when Dio is the chosen provider.
Read the [paved-road guide](../../docs/guides/paved-road-platform.md).

## Availability

The workspace contains the `1.0.0-rc.5` source candidate. Supported Git use
requires coordinates from a matching tagged GitHub Release; otherwise there is
no supported consumption path.
