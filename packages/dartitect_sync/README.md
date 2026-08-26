# dartitect_sync

[Português (Brasil)](README.pt-BR.md)

## Purpose

Pure-Dart, provider-neutral synchronization primitives for Dartitect. Consumers
define datasets, dependency order, checkpoints, leases, retry/conflict policy,
and provider adapters. The engine never imports Flutter, HTTP, storage, or a
platform scheduler.

Each foreground or headless entrypoint creates and disposes its own owned graph.
Only validated command data crosses isolate boundaries.

## Use it

Define a `SyncDataset` per local-authority dataset, validate dependencies with
`SyncDependencyGraph`, inject checkpoint and optional lease ports, then await
`engine.start().done`. Expected failures return `Err`; unexpected exceptions
keep their stack and are rethrown. See the
[runnable example](example/dartitect_sync_example.dart).

## Consumer policy

The application owns local transactions, remote mapping, idempotency, retry,
conflict resolution, authentication, scheduling, payload validation, durable
cross-process deduplication, and provider resources. Checkpoint stores must use
the supplied fencing token to reject a stale lease holder.
