# dartitect_workmanager

## Purpose

Stable, opt-in adaptation between Workmanager callbacks and Dartitect's
versioned `JobDispatcher` contract. Every callback constructs and disposes a
fresh consumer graph while keeping credentials and business payloads outside
the scheduler boundary.

## When to use

Use it when Android, iOS, macOS, web, or Linux must schedule a Dartitect job or
headless-sync graph through `workmanager ^0.10.9`.

## When not to use

Do not use it as a Windows scheduler, credential store, domain queue, recurrence
policy, retry engine, or replacement for consumer-owned native configuration.

## Platforms and entrypoints

Import `package:dartitect_workmanager/dartitect_workmanager.dart`. Android,
iOS, and macOS report stable platform maturity. Web and Linux report preview
upstream capability with explicit limitations. Windows returns typed
`DartitectWorkmanagerUnsupported` without invoking the plugin.

## Mental model and data flow

The foreground graph creates a scalar `DartitectWorkmanagerEnvelope` and asks
`DartitectWorkmanagerScheduler` to register it. The top-level plugin dispatcher
constructs one `DartitectWorkmanagerCallback`; each execution decodes the
envelope, builds a fresh `OwnedGraph<JobDispatcher<...>>`, executes one job,
writes an optional sanitized receipt, and disposes the graph.

## Minimal workflow

```dart
final envelope = DartitectWorkmanagerEnvelope(
  jobId: 'catalog-refresh-42',
  definition: 'catalog-refresh',
  deadline: DateTime.now().toUtc().add(const Duration(minutes: 10)),
  payload: const <String, Object?>{'dataset': 'catalog'},
);

final result = await DartitectWorkmanagerScheduler().schedule(envelope);
```

Register `runDartitectWorkmanagerDispatcher(callback)` from a consumer-owned
top-level callback. Load credentials and provider graphs inside `createGraph`.

## Public API tour

`DartitectWorkmanagerCapability` reports closed platform maturity and static
limitations. `DartitectWorkmanagerEnvelope` validates a versioned, scalar-only
schema. `DartitectWorkmanagerScheduler` initializes, schedules, and cancels
through typed outcomes. `DartitectWorkmanagerCallback` adapts plugin execution
to `JobDispatcher`; `DartitectWorkmanagerReceiptStore` is the consumer-owned
durability port.

## Ownership and lifecycle

The application owns the scheduler and plugin registration. Every accepted
callback owns a fresh dispatcher graph, deadline timer, and cancellation source
and releases all of them in `finally`. Provider clients, databases, credential
stores, receipt persistence, and native configuration remain consumer-owned.

## Failure, cancellation, and concurrency

Plugin failures retain their original stack in
`DartitectWorkmanagerOperationFailed`. Invalid envelopes, typed job failures,
unexpected crashes, deadline cancellation, and platform stop callbacks produce
closed, payload-free receipt statuses. The consumer chooses retry and recurrence
policy; a repeated job ID remains the durable deduplication key.

## Prohibited uses and limitations

- Do not serialize credentials, provider objects, errors, stacks, or domain
  entities in an envelope or receipt.
- Do not reuse the foreground application graph in a background callback.
- Do not infer exactly-once delivery from Workmanager execution.
- Do not report Web/Linux preview capability as mature native parity.
- Do not invoke a plugin channel after typed Windows unsupported is returned.

## Testing

Run `flutter test`. Cover closed-schema decoding, typed unsupported behavior,
plugin failure, cancellation, deadline expiry, typed job failure, unexpected
crash, a fresh graph per callback, sanitized receipts, and zero residual graph
resources. Platform canaries exercise the supported upstream hosts without real
network traffic or credentials.

## Related packages and guides

`dartitect_jobs` owns the provider-neutral dispatcher and `dartitect_sync` owns
headless dataset contracts. Read the
[paved-road guide](../../docs/guides/paved-road-platform.md) and
[reactive runtime guide](../../docs/guides/reactive-runtime.md).

## Availability

The workspace contains the `1.0.0-rc.9` source candidate. Supported Git use
requires coordinates from a matching tagged GitHub Release; otherwise there is
no supported consumption path.
