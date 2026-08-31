# dartitect_sync

## Purpose

Provider-neutral primitives for four separate offline/background concerns:
durable mutation plus outbox delivery, ordered dataset synchronization, and
headless synchronization commands, plus explicit trigger coordination. The
package imports no Flutter, HTTP, database, or platform scheduler.

## When to use

Use it when correctness depends on an explicit durable outbox, a validated
dataset dependency graph with checkpoints, or a versioned headless command
whose acceptance and terminal result must be distinguished.

## When not to use

Do not use it for an in-memory refresh with no durability or ordering
requirements. It is not a repository, transport, database schema, scheduler,
background-service plugin, conflict resolver, retry oracle, or exactly-once
delivery system.

Config-v2 tooling materializes an `OperationalStorageContextManifest` once per
named provider context. It contains only validated dataset/partition/codec/
retention/transaction-boundary facts and contiguous operational migrations.
It never defines domain tables, semantic mappers, conflict policy, or an
automatic retention executor.

## Platforms and entrypoints

Import `package:dartitect_sync/dartitect_sync.dart`. The package is pure Dart and
supports the Dart VM, Flutter, and web. A host that runs work in another isolate
must separately provide isolate/platform scheduling and transferable payloads.

## Mental model and data flow

Choose one mechanism for each concern:

1. A `MutationCommand` asks the consumer's `MutationOutboxStore` to atomically
   apply the local change and enqueue one `OutboxOperation`. The local state is
   authoritative immediately. Delivery reuses the operation's idempotency key
   and persists every attempt/state transition.
2. A `SyncEngine` validates a DAG, reads the confirmed checkpoint for each
   eligible dataset, runs prerequisites first, lets the dataset atomically apply
   remote data locally, and only then writes the new checkpoint. An optional
   journal records payload-free run facts; an optional lease supplies fencing
   authority.
3. A `HeadlessSyncEndpoint` adapts a versioned sync definition through
   `dartitect_jobs`, deduplicates a bounded request set, acknowledges
   acceptance, creates one fresh `OwnedGraph`, and produces a terminal
   completion/failure acknowledgment without hidden retries.
4. A `SyncTriggerCoordinator` subscribes to injected manual, lifecycle,
   connectivity, scheduler, push, and session sources. It unions datasets,
   keeps the highest-priority cause, permits at most one coalesced follow-up per
   active run, and fences every batch by session generation.

These flows may call the same repositories, but their durability records and
retry ownership are distinct. A mutation outbox is not a dataset checkpoint; a
run journal is not domain data; a headless receipt is not proof of remote
exactly-once execution.

## Minimal workflow

```dart
import 'package:dartitect/dartitect.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

Future<void> main() async {
  final checkpoints = _MemoryCheckpoints<String, int>();
  final graph = SyncDependencyGraph<String>(
    keys: const <String>['records', 'search_index'],
    dependencies: const <String, List<String>>{
      'search_index': <String>['records'],
    },
  );
  final engine = SyncEngine<String, int, StateError>(
    graph: graph,
    checkpoints: checkpoints,
    datasets: <SyncDataset<String, int, StateError>>[
      SyncDataset<String, int, StateError>(
        key: 'records',
        synchronize: (context) async {
          context.cancellation.throwIfCancelled();
          // Commit downloaded records locally before returning the checkpoint.
          return const Ok(SyncDatasetOutcome<int>.checkpoint(1));
        },
      ),
      SyncDataset<String, int, StateError>(
        key: 'search_index',
        synchronize: (context) async =>
            const Ok(SyncDatasetOutcome<int>.unchanged()),
      ),
    ],
  );

  try {
    final report = await engine.start().done;
    assert(report.succeeded);
  } finally {
    await engine.disposeAsync();
  }
}

final class _MemoryCheckpoints<K, C> implements SyncCheckpointStore<K, C> {
  final Map<K, C> values = <K, C>{};

  @override
  Future<C?> read(K key, CancellationSignal signal) async => values[key];

  @override
  Future<void> write(
    K key,
    C checkpoint,
    CancellationSignal signal, {
    int? fencingToken,
  }) async {
    signal.throwIfCancelled();
    values[key] = checkpoint;
  }

  @override
  Future<void> remove(K key, CancellationSignal signal) async {
    signal.throwIfCancelled();
    values.remove(key);
  }
}
```

Production stores replace the in-memory checkpoint port and commit the dataset
plus fencing comparison atomically where fencing is required.

## Public API tour

Durable mutation and outbox:

- `MutationCommand` (also aliased as `MutationLane`) owns bounded sequential
  lanes per aggregate key and bounded concurrency across keys.
- Optional `RetryExecutor` integration reuses `dartitect_resilience` while
  retaining existing constructors; uncertain outcomes always stop automatic
  retry.
- `MutationOutboxStore` defines atomic local/enqueue, state persistence,
  recovery loading, and explicit compensation.
- `OutboxOperation` preserves a stable idempotency key, aggregate key, argument,
  attempt count, and sync state.
- `MutationExecution`, `CommitDisposition`, `EntitySyncState`,
  `MutationFailurePolicy`, `RetryClassification`, and `RetryKind` make accepted,
  queued, rejected, conflicted, uncertain, retry, and success states explicit.

Dataset synchronization:

- `SyncDependencyGraph` rejects missing keys, duplicates, self-edges, and cycles,
  then produces a stable `SyncPlan`.
- `SyncDataset` and `SyncDatasetContext` provide checkpoint, cancellation,
  deadline, run ID, and optional `SyncAuthority` to consumer code.
- `SyncEngine.start` returns a single-use `SyncRun` with bounded progress and a
  terminal `SyncReport`.
- `SyncCheckpointStore` persists opaque consumer checkpoints.
- `SyncLeaseStore`/`SyncLease` provide mutual exclusion, renewal, expiry, and a
  monotonic fencing token.
- `SyncRunJournal` stores ordered `SyncJournalEntry` facts and reconstructs
  `IncompleteSyncAttempt` summaries for `resumeIncomplete`.
- `SyncDatasetReport` and `SyncBoundaryReceipt` expose application, checkpoint,
  journal, lease-release, and cleanup outcomes independently.

Headless synchronization:

- `SyncCommandEnvelope` carries protocol version, request ID, UTC deadline, and
  consumer-validated transferable payload.
- `HeadlessSyncEndpoint.accept` returns `SyncCommandReceipt` with immediate
  acceptance/rejection and a terminal future; `handle` waits for the terminal.
- Ack variants distinguish accepted, pre-admission rejected, completed, and
  expected failed outcomes. `HeadlessSyncHandler` is built inside the fresh
  graph.

Trigger coordination:

- `SyncTriggerSources` supplies exactly six inert streams; `start()` attaches
  and `disposeAsync()` removes every listener and drains active work.
- `SyncTriggerIntent`, `SyncTriggerBatch`, and `SyncTriggerCause` keep dataset
  selection, deadline, generation, and priority explicit.
- `SyncTriggerPhase` exposes `idle`, `scheduled`, `running`, `blocked`,
  `offline`, and `backoff`. Offline resumes only from injected connectivity;
  blocked/backoff resume only through explicit consumer calls.
- `SyncTriggerRunDisposition` reports consumer policy. The coordinator creates
  no backoff timer, retry, scheduler registration, or dataset policy.

## Ownership and lifecycle

The engine, runs, mutation command, trigger coordinator, and headless endpoint
are owned by the composition that creates them. Checkpoint, lease, journal,
outbox, repository, transport, clock, observer, and provider resources are
borrowed unless the consumer graph explicitly owns them. Dispose trigger
producers first, then coordinator/engine/endpoint/commands, then persistence
and transport dependencies.

Every foreground or headless execution builds or uses a graph owned by its
entrypoint. Only validated data crosses isolates. Headless disposal rejects new
commands, cancels active handlers, waits for terminal work, and disposes each
fresh graph.

The consumer owns schemas, codecs, retention, authentication, scheduling,
idempotency scope, remote mapping, local transactions, conflict policy, retry
classification, compensation, and distributed protocol.

## Failure, cancellation, and concurrency

Expected mutation or dataset failures remain typed results/reports. Unexpected
exceptions retain their original stack. `SyncRunTerminalException.report` is a
terminal receipt: inspect application, checkpoint, journal, lease-release, and
cleanup boundaries before deciding whether replay is safe. If application
succeeded but checkpointing failed, the result is uncertain/incomplete and must
not be blindly replayed.

Cancellation and deadlines are cooperative. A dataset may have committed before
a later boundary observes cancellation, so terminal receipts remain
authoritative. Dependencies run only after their selected prerequisites
succeed. One engine may own multiple runs; a configured lease controls external
authority, not in-process scheduling.

Trigger deadlines cancel only the selected runner signal. Session-generation
changes and offline transitions cancel active work and discard stale-generation
completion. A blocked or backoff disposition never schedules its own retry;
the consumer must release it and provide any reschedule policy.

For fencing, call `ensureAuthority()` immediately before the local commit and
compare `fencingToken` inside the same storage transaction. Checking the lease
without atomic compare-and-commit provides no fencing guarantee.

Mutation delivery is at least once. Same-key work is sequential; active keys and
per-key queues are bounded. Automatic retry is opt-in and bounded; uncertainty,
conflict, definitive rejection, lane crash/resume, and compensation remain
explicit. Headless request retention is bounded, and duplicates share the
recorded terminal future while retained.

## Prohibited uses and limitations

- Never advance a checkpoint before the corresponding local coverage commits.
- Never treat a journal as a source of checkpoint authority or domain payload.
- Never claim a lease fence when storage cannot atomically reject stale tokens.
- Never generate a new idempotency key for a retry of the same operation.
- Never compensate automatically after an uncertain remote outcome.
- Never transfer live clients, databases, Stores, owners, or handlers across an
  isolate.
- Never assume exactly-once delivery, global scheduling, or crash-proof
  persistence from in-memory ports.
- Never treat trigger coalescing as retry, scheduler, connectivity, or session
  ownership.

`resumeIncomplete` starts replacement attempts for incomplete journal summaries
and omits journal-confirmed completed datasets, but the checkpoint store remains
the coverage authority.

## Testing

Run `dart test`. Cover graph validation/order, atomic local-plus-outbox rollback,
offline enqueue, duplicate delivery, recovery, bounded retry, conflicts,
uncertainty, explicit compensation, checkpoints, crash journaling, lease
renewal/expiry/fencing, cancellation, deadlines, cleanup failures, terminal
receipt inspection, headless duplicate requests, protocol rejection, and graph
teardown. `dartitect_testing` includes in-memory stores, manual leases/clocks,
crash harnesses, and sync contract harnesses.
Trigger tests should also cover cause priority, dataset union, one follow-up,
generation fencing, offline/backoff release, deadline cancellation, stream
errors, and zero remaining listeners/timers after teardown.

## Related packages and guides

Use `dartitect_drift` or `dartitect_objectbox` for consumer-owned checkpoint,
journal, and transaction adapters; `dartitect_isolates` for a typed native
worker; and `dartitect_flutter` for local-authority presentation. Read
[implementation recipes](../../docs/guides/implementation-recipes.md),
[commands/results/effects](../../docs/guides/commands-results-effects.md), and
[composition/lifecycle/isolates](../../docs/guides/composition-lifecycle-isolates.md).

## Availability

The workspace contains the `1.0.0-rc.9` source candidate. Supported
Git consumption requires one compatible cohort from a tag with a corresponding
published GitHub Release, using its Release-note coordinates. If no compatible
Release exists, there is no supported consumption path. See the
[Git candidate consumption guide](../../docs/guides/git-candidate-consumption.md).
