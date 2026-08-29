# Opting into the reactive runtime

This guide describes a Dartitect-owned feature graph. `native_strict` is the
only architecture profile: a Dartitect feature graph cannot coexist with a
second application-state runtime. Migrate the whole ownership boundary before
making Dartitect authoritative for it.

The `package:dartitect_flutter/dartitect_flutter.dart` entrypoint is the stable
thin surface for `ViewModelHost`, `Command0`/`Command1`, `ListenableSelector`,
scope, and error binding.

## Entrypoints

Import `package:dartitect_flutter/dartitect_flutter_reactive.dart` only when a
feature adopts the owned reactive graph, resources, collections, or headless
builders. The headless entrypoint never exports Material; consumer-owned
presentation composes these builders with Material or Cupertino widgets.

## Ownership

Create one reactive owner per explicit app, session, route, or background
composition boundary. Inject repositories and adapters through constructors.
Dispose widgets and commands first, then observations, queries and clients,
then the owner. Consumer-owned Stores, clients, and telemetry destinations
remain borrowed and are closed by the consumer.

## Atomic graph

`ReactiveOwner` creates values and typed-key computeds. Perform every write
inside `owner.update`; nested updates join the outer transaction and listeners
run only after all affected computeds stabilize. The observable phase machine
is `idle → write → compute → commit → notify`; terminal teardown uses `dispose`
and `disposed`. Writes or new definitions during compute/commit are rejected,
never flushed implicitly. A compute crash preserves the previous graph snapshot
and revision, reports through the injected `ReactiveComputeReporter`, and is
rethrown with its original stack trace. Listener failure occurs after commit:
it is reported and isolated, every other listener continues, and the mutation
caller retains its successful return value.

Every `ReactiveKey<T>` requires a stable namespace, positive definition
revision, and non-empty fingerprint. Identity is owner-local and consists of
type, namespace, and name. Reuse also requires matching definition metadata,
kind, dependencies, and equality; otherwise
`ReactiveKeyConflictException` reports the existing and incoming definitions.
Compatible computed registration refreshes its closure while preserving state.
Use `ViewModelHost.onReassemble` to perform that rebinding after hot reload.
Hot restart builds a new host/owner and resets ephemeral graph state.
Every node directly implements Flutter's `ValueListenable<T>`. Equality is
node-local and defaults to `==`; supply an explicit equality callback when the
domain's meaningful-change rule differs.

Dispose the owner to remove every edge and listener. A disposed owner is
terminal and rejects reads, node creation, listener registration, and writes.

## Resource lifecycle

Resource data (`waiting`, `ready`, `failed`, or `crashed`) is independent from
upstream temperature (`hot`, `warm`, or `cold`). Choose an `ActivationPolicy`,
retain lifetime with a `ResourceLease`, and let `ReactiveObservation` pause
activity when `TickerMode` is disabled. Warm resources retain last-known data
but have no active upstream; cold resources discard both.

Use `AsyncLifecycleBarrier` around asynchronous source work. Disposal closes
admission first, requests cooperative cancellation, drains admitted operations,
and rejects every stale publication before releasing the graph.

## Live sources and backpressure

Implement `ReactiveSource<T, F>` as a factory for activation-local sessions.
Each session owns the stream subscription, query, or cursor it creates; injected
Stores and clients remain borrowed. `LiveResource<T, F>` performs the initial
authoritative read and reopens a fresh session for every hot generation.

The default `SourceBackpressure.latestWhileBusy` runs one read and remembers at
most one dirty rerun while busy. Choose `everyEmission`, `coalesceMicrotask`, or
`coalesceFrame` only when that boundary is part of the feature contract.
Expected `Err<F>` values retain last-known data. An unexpected crash is reported
once, suspends and closes the source, and resumes only through explicit
`retry()`. Disposal cancels and drains admitted work before closing the session.

Use `FutureReactiveSource`, `StreamReactiveSource`,
`ListenableReactiveSource`, or `ValueListenableReactiveSource` when adapting
native primitives. Each hot activation creates a fresh session/subscription.
Streams carry typed `Result<T, F>` events; an actual stream error remains an
unexpected crash with its original stack rather than being converted to `F`.

## Derived async resources

Use `DerivedAsyncResource<T, F>` only when an asynchronous value has an
explicit, non-empty set of Flutter `Listenable` dependencies. The adapter
subscribes during a hot generation, removes every listener when that generation
closes, and delegates its public state and observation lifecycle to one
`LiveResource`. It performs no implicit read tracking.

Each dependency change advances a generation and uses
`SourceBackpressure.restartLatest`: the active loader receives cooperative
cancellation, drains, and only then admits the newest read. The source and
resource generation guards reject a late result even when the loader ignores
cancellation. `LiveResourceStalePolicy` chooses preserved last data, discarded
last data, or stale-while-revalidate. The derived adapter deduplicates equal
ready data with `==` by default; inject the domain's equality when needed.

```dart
final resource = DerivedAsyncResource<AccountView, LoadFailure>(
  dependencies: <Listenable>[session, filters],
  stalePolicy: LiveResourceStalePolicy.staleWhileRevalidate,
  load: (read) => repository.loadAccountView(
    session.value,
    filters.value,
    cancellation: read.cancellation,
  ),
);
```

For keyed sharing, return `DerivedAsyncResource(...).liveResource` from an
existing `ResourceFamily<K, T, F>` factory. The family—not the dependency value
or loader—owns key equality, leases, idle TTL, count/weight limits, prewarm, and
eviction. The API is stable under ADR 0044 after passing generation, lifecycle,
resource-census, and diagnostics gates; it still rejects implicit tracking and
global hooks.

## Invalidation and causal refresh

Create typed groups through `ReactiveOwner.invalidationGroup<K>()`, then bind
borrowed `LiveResource` instances to feature keys. Every group invalidation has
a monotonic revision. A hot resource starts bounded source work immediately; a
warm resource marks its retained snapshot stale and refreshes on reactivation;
a cold resource starts no work and retains no stale snapshot. Disposing either
the owner or resource detaches the registration without disposing the other.

Use the refresh type that states the completion point your UI actually needs:

- `RemoteRefresh<T, F>` completes with the remote action;
- `LocalCommitRefresh<R, F>` completes with a `LocalCommitReceipt<R>`;
- `ObservedLocalRefresh<T, R, F>` completes only after a source publishes an
  `ObservedValue<T, R>` with the receipt's exact revision.

The observed form requires a positive timeout and a consumer callback that maps
timeout to `F`. Waiters are indexed by typed revision, timers are operation
owned, and timeout/disposal removes both without patching authoritative data.
Different refresh completion points have different static result types, so they
cannot be substituted accidentally.

## Bounded resource families

Create a `ResourceFamily<K, T, F>` at an explicit composition boundary and
inject a key-to-`LiveResource` factory. Equal keys share only inside that family;
another family always creates an independent resource. Acquire a `FamilyLease`
for every consumer retention and release it idempotently.

`FamilyCachePolicy<K, T>` bounds idle retention with a positive TTL,
`maxIdleEntries`, and `maxIdleWeight`. `weightOf` receives the typed key and
optional retained value. When limits require eviction, expired entries come
first, followed by lower recreation cost, least-recently-used access, and the
stable creation ordinal. Active leases, observers, and hot resources are never
evicted. An entry larger than the complete weight budget is disposed directly
without displacing valid cached entries.

`prewarm(key, duration)` is family-owned: it retains the entry, owns a temporary
observation and timer, and then releases all three. Invalidation delegates to
the same typed rules as `InvalidationGroup`. Eviction removes an entry from the
index before asynchronous disposal, so reacquisition creates a fresh generation
even while the old one drains. Disposal failures remain surfaced as aggregated
lifecycle cleanup failures and never reinsert the failed entry.

## Incremental live collections

`LiveCollection<K, T>` keeps stable item nodes and separates its signals:
`keys` changes only for membership/reorder, `length` only for membership count,
`item(key)` only for that projected value, and `changes` emits typed structural
facts. Every update selects `replaceAll`, `diffByKey`, or `versionedByKey`
explicitly; there is no hidden size threshold.

The versioned policy caches `key -> version -> projection`, so an unchanged
version reuses its projection. The collection validates all keys and calculates
the complete next cache before publication. A duplicate key or projection crash
therefore preserves the prior order, nodes, cache, revision, and notifications.
Membership, reorder, and item values become visible as one synchronous batch.

Removed nodes publish a tombstone (`isPresent == false`) and remain stable while
they have listeners or their configured warm retention has not expired. A
reattached key reuses the node; expiry or collection disposal cancels timers and
detaches it. For ObjectBox, `ObjectBoxVersionedProjection` accepts
consumer-owned ID, version, and projection callbacks—entities and generated
model code remain outside Dartitect.

Projection remains inline unless `updateProjected` receives
`ProjectionExecution.background` and an injected executor. The main isolate
computes keys/versions, sends only changed `CollectionProjectionInput` values,
and commits a complete `CollectionProjectionOutput` set only when its generation
is still current. A crash, cancellation, dispose, missing/duplicate key, or
stale completion preserves the stable collection snapshot.
The current generation exposes `CollectionProjectionStatus.crashed` with its
original stack until an explicit later projection succeeds; there is no
automatic retry.

`IsolateProjectionExecutor` owns and drains generic worker isolates. For a real
ObjectBox Store, use `ObjectBoxProjectionExecutor` over `Store.runAsync` or the
provider's `Query.findAsync`; create the worker graph/query from transferable
configuration and close it in `finally`. The original Store remains borrowed
and closes only after collection and executor teardown.

## Selectors, debounce, and local-first pages

Use `ReactiveSelector<S, T>` when a derived value must exist outside a widget.
It subscribes to one borrowed `Listenable`, evaluates on each source signal, and
notifies downstream only when its configurable equality says the selection
changed. The selector owns that subscription and detaches it on disposal.

`DebouncedReactiveValue<T>` subscribes to a borrowed `ValueListenable`, owns one
injected quiet-period timer, and publishes only the latest distinct value.
`flush()` is explicit; disposal cancels a pending timer and never publishes the
stale value.

`PagedLiveResource<C, K, T, F>` keeps remote data out of presentation state.
The injected request returns a `PageBatch`; the resource deduplicates it by the
consumer key callback and passes a `PageWrite` to the repository-owned local
transaction. The transaction returns a `PageWriteReceipt`, but the cursor does
not advance until the borrowed `LiveResource<PagedLocalSnapshot<K, T>, F>`
publishes the receipt's exact revision. Its exposed `LiveCollection` is updated
only from that local snapshot.

Refresh uses a joining command lane, load-more drops reentrant calls, and search
uses restart-latest. Cancellation is checked before the local write, so a stale
cooperative search generation cannot patch the database or collection. Expected
request, write, or observation-timeout failures preserve the last local data and
valid cursor. The synchronous `timeline` stream exposes request, response,
local-commit, local-observation, and completion phases without retaining an
unbounded transcript.

## Offline-first mutations and outbox recovery

`MutationCommand<A, K, T, F>` schedules mutations sequentially per entity key.
The injected `MutationOutboxStore` owns the only authoritative local write: its
`applyLocalAndEnqueue` implementation must change domain data and persist the
`OutboxOperation` in one transaction. Dartitect never patches a presentation
list in memory and never defines consumer entities, outbox schema, endpoints,
or conflict rules.

Every operation carries a non-empty consumer-scoped idempotency key reused for
all at-least-once attempts. A remote success becomes `committed/synced` only
after the store persists that acknowledgement. An expected failure is mapped by
`MutationFailurePolicy` to queued/pending, rejected, conflicted, or uncertain.
Queued and uncertain changes are not rolled back automatically. Definitive
rejection can be followed by the explicit `compensate` transaction.

Retry is manual by default. `RetryClassification.transient` opts one failure
class into bounded exponential retries while preserving the same operation and
idempotency key. An unexpected delivery crash is reported once, rethrown, marks
the durable operation uncertain when delivery may have committed, and stops
only that key's lane. Audit the provider/repository state, persist a deliberate
pending decision, call `resume(key)`, and then retry. `recoverPending()` on a new
session deduplicates idempotency keys and drains only pending records; uncertain
records remain untouched until that explicit decision.

For ObjectBox, place both consumer entity writes inside
`ObjectBoxMutationTransaction.run`. Its synchronous write transaction converts
a typed `Err` into a rollback and returns the same failure; unexpected crashes
also roll back and are rethrown. The Store remains borrowed.

## Causal diagnostics without domain payloads

Outer `ReactiveOwner.update` calls and terminal `MutationCommand` operations
can publish a `ReactiveChangeEvent`. The event is deliberately limited to
source, outcome kind, a pre-registered static `ChangeCause`, revisions,
monotonic duration, and listener count. Register custom causes once at the
composition root and pass the exact identity; reconstructed or dynamic causes
are rejected before state changes begin.

Observers are injected as explicitly owned or borrowed registrations. Use the
bounded, memory-only `ReactiveJournal` for local diagnostics or the
`ReactiveObserverLoggerAdapter` for sanitized observability. Observer failure
is isolated and reported once, then that observer is disabled. Neither events
nor the journal store domain payloads, keys, error text, or identity.

For cross-runtime topology and lifecycle, protocol version 1 adds fixed subject
categories for owner, node, command, resource, family, effect, sync, and
isolate. A `DartitectDiagnosticEvent` contains only its schema version,
emitter-local sequence, fixed category/phase, opaque process-local IDs,
generation, and revision. The exact decoder rejects extra fields, so domain
values, keys, queries, error messages, stacks, and identities have no protocol
slot.

Create `DartitectDiagnosticsEmitter` at a composition boundary with an
explicitly owned or borrowed reporter. `DartitectDiagnosticBuffer` is bounded,
overwrites its oldest event, and clears every event reference on dispose.
`SafeDartitectDiagnosticReporter` isolates reentrancy and destination failure.
Select `off`, `lifecycle`, or `topology`; off allocates no subject ID and none of
the modes changes runtime outcomes. Failure and crash terminal facts are never
sampled inside an enabled lifecycle stream.

`LiveResource` and `DerivedAsyncResource` accept a borrowed diagnostic subject
of fixed kind `resource`. The resource emits state/lifecycle facts, never its
data or failure. Use `DiagnosticsTopologyHarness` from `dartitect_testing` to
reconstruct opaque relationships and terminal lifecycle in tests. IDs must
come from the emitter's injected generator and must never be application IDs.
The construction/reporting APIs are stable under ADR 0044 after consumer,
performance, ownership, and discard review.

## Headless builders and consumer presentation

The reactive entrypoint provides `ReactiveValueBuilder`,
`LiveResourceBuilder`, `LiveCollectionBuilder`, and `PagedLiveBuilder` without
importing Material. Each widget borrows its input and owns only its listener or
`ReactiveObservation`. `TickerMode` disables that observation and every
offscreen rebuild; unmount detaches synchronously, while the route/composition
root drains and disposes the borrowed resource outside `build`.
The optional `onBuild` hook receives only `FlutterBindingBuildEvent`: binding
kind, monotonic count, callback duration, local handle count, and ticker state.
Observer failures are isolated and values, keys, queries, identities, and error
messages are never included.

Collection builders observe key structure only. Render each `LiveItem` through
`ReactiveValueBuilder` so one item update does not rebuild the complete list.
Stable `ValueKey` values and `findChildIndexCallback` preserve row State across
reorder. Callbacks and one-shot effects remain route-owned and are never replayed
by a builder.

Material and Cupertino screens render waiting/ready/failure/crash states in the
application without stringifying failures automatically. Use stable Semantics
live regions, keyboard-focusable controls, text scaling, and route-owned
retry/refresh/load-more callbacks. The reference workloads demonstrate this
consumer boundary while disposing the paged resource before its local source.

The advanced entrypoints are stable in `1.0.0-rc.6` and remain explicit opt-ins.
