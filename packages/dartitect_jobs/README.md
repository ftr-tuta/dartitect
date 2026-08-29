# dartitect_jobs

## Purpose

Provider-neutral contracts and a bounded dispatcher for versioned headless
work. Every accepted job gets a fresh owned graph, cancellation, an absolute
deadline, an execution ID, and typed progress.

## When to use

Use it when a host must accept, deduplicate, execute, and drain generic
background work without coupling application handlers to a scheduler SDK.

## When not to use

Do not use it as a native scheduler, recurring-work service, credential store,
payload schema, distributed queue, or hidden retry layer.

## Platforms and entrypoints

Import `package:dartitect_jobs/dartitect_jobs.dart`. It is pure Dart and supports
the Dart VM, Flutter, and web; native background registration remains external.

## Mental model and data flow

A versioned `JobEnvelope<P>` selects a registered `JobDefinition`. Admission
validates protocol, payload, deadline, deduplication, and capacity before
building one `OwnedGraph<JobHandler<...>>`. Acceptance and terminal results are
separate.

## Minimal workflow

```dart
final dispatcher = JobDispatcher<MyPayload, int, MyFailure, MyProgress>(
  definitions: [
    JobDefinition(
      name: 'refresh',
      createGraph: buildRefreshGraph,
    ),
  ],
);
```

## Public API tour

`JobEnvelope`, acknowledgements, and `JobReceipt` model transport-neutral
admission and completion. `JobDefinition`, `JobHandler`, and
`JobExecutionContext` define typed work. Optional receipt-store and lease ports
support durable deduplication and fencing.

## Ownership and lifecycle

The composition root owns the dispatcher. Each admitted job owns one graph and
disposes it after terminal work. Stores, lease providers, scheduler SDKs, and
progress reporters are borrowed unless the surrounding graph says otherwise.

## Failure, cancellation, and concurrency

Expected handler failures are typed acknowledgements; unexpected exceptions
keep their stack. Deadlines and receipt cancellation are cooperative. Active
jobs and remembered IDs are bounded, and duplicate receipts share one terminal.

## Prohibited uses and limitations

- No hidden retry, recurrence, authentication, or native registration.
- No live client, database, Store, or owner in a job envelope.
- No exactly-once claim from an in-memory deduplication window.
- No unbounded concurrency or receipt retention.

## Testing

Run `dart test`. Cover protocol and payload rejection, capacity, deduplication,
deadlines, cancellation, graph disposal, store reuse, fencing, progress, and
zero active or retained resources after shutdown.

## Related packages and guides

`dartitect_sync` adapts headless sync definitions through this package. Use
`dartitect_isolates` for a typed isolate host. Read the
[paved-road guide](../../docs/guides/paved-road-platform.md).

## Availability

The workspace contains the `1.0.0-rc.6` source candidate. Supported Git use
requires coordinates from a matching tagged GitHub Release; otherwise there is
no supported consumption path.
