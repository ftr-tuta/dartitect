# Composition, lifecycle, and isolates

[Português (Brasil)](composition-lifecycle-isolates.pt-BR.md)

## Composition roots

Build explicit application, session, feature, route, operation, and receiver-
isolate graphs. Create only the scopes an application needs, but never let a
child scope outlive its parent. Prefer constructor injection. Do not introduce
global runtimes, Stores, Dio clients, Hubs, service locators, or cross-isolate
live objects.

## 1.0 lifecycle contract matrix

The following matrix is normative for 1.0. `E`, `T`, and `P` mean ephemeral,
temporary, and persisted durability as defined below.

| Lifetime | Root and terminal event | Owned boundary | Borrowed boundary | Transfer and durability | Required teardown |
| --- | --- | --- | --- | --- | --- |
| Application | Process/application composition; app shutdown | Process-wide clients, Stores, executors, and owned observability | Host/platform services with an external owner | Transaction commit; `E/T/P` | All child scopes, then application dependents before dependencies; observability flush/dispose last |
| Session | Authentication, account, or tenant generation; logout, switch, or parent shutdown | Session credentials, clients, repositories, and caches | Application services | Transaction commit; `E/T/P` | Operations, routes, and features; then session dependents before dependencies |
| Feature | State deliberately shared by multiple routes; feature deactivation or parent shutdown | Feature commands, resources, watchers, and caches | Session/application services | Transaction commit; `E/T/P` | Operations and routes; then feature dependents before dependencies |
| Route | One route or ViewModel composition; unmount/removal or parent shutdown | ViewModels, bindings, observations, and route-local resources | Feature/session services | Transaction commit; `E/T`; persisted writes use a longer-lived Store | Operations first; then bindings/observations before their sources |
| Operation | One admitted command/read/resource attempt; success, failure, cooperative cancellation, deadline, or parent shutdown | Attempt-local cancellation, timers, subscriptions, queries, and temporary artifacts | The route/feature/service used by the attempt | Transaction commit; `E/T`; persisted results use a longer-lived Store | Close admission, drain the admitted attempt, then release attempt resources |
| Isolate | One receiver entrypoint and its local graph; graceful stop, crash cleanup, or process end | Receiver-local ports, workers, attached Store wrappers, queries, and graph | No live borrowed object crosses the boundary | Serializable messages only; `E/T/P` remain receiver-local | Stop admission, drain or reach the deadline fallback, run receiver-local `finally`, close ports/graph |

## Ownership and transfer rules

- **Owned:** the acquiring scope registers the value only after acquisition
  succeeds, releases it exactly once, and prevents use after teardown starts.
- **Borrowed:** the borrower never registers or closes the value. Its provider
  must outlive every borrower.
- **Transferred:** `ResourceTransaction.commit()` atomically moves the complete
  owned set to one `OwnedGraph` and makes the transaction terminal.
  `OwnedRuntimeSlot.replaceGraph()` may then assume ownership of that complete
  graph. Borrowed values do not move. Dartitect exposes no individual
  live-resource transfer between owners, generations, or isolates.

`OwnedRuntimeSlot.replace()` builds a new transaction before publication. On a
successful replacement it closes old admission, publishes the new committed
graph, drains old work, and then tears down the old graph. Failed construction
leaves the previous generation valid. If old teardown fails after publication,
the replacement throws `OwnedRuntimeReplacementCleanupException`; its
`publishedGeneration` is already authoritative and its cleanup error describes
only the previous graph. Do not retry the replacement blindly.

## Durability

- **Ephemeral (`E`)** exists only in the live graph. Teardown closes or discards
  it; examples include timers, controllers, subscriptions, queries, and leases.
- **Temporary (`T`)** may use disk or platform storage but is replaceable. The
  owner that creates it registers both handle closure and removal, and startup
  recovery removes crash leftovers before reuse.
- **Persisted (`P`)** data survives graph teardown and restart. The graph still
  owns and closes its live Store/file/query handles; only an explicit domain
  retention or deletion operation may remove the data.

Durability describes data, not handle ownership. A persisted Store wrapper is
still ephemeral to its owning graph.

## Teardown and failure

Acquire providers before dependents and register each owned value immediately,
so `ResourceOwner` releases dependents before dependencies in reverse order.
Every scope follows the same terminal sequence:

1. Reject new work and signal cooperative cancellation where applicable.
2. Drain work already admitted; a documented deadline may force only the
   isolate/process boundary.
3. Release child scopes and owned resources in reverse registration order.
4. Skip borrowed values, continue after each cleanup failure, and report all
   failures together as `ResourceCleanupException`.
5. Clear registrations, become terminal, reject future use, and share the same
   completion with concurrent or repeated disposal calls.

Construction failure rolls back only acquisitions that completed. A failure
during rollback is preserved separately from the original construction error.

## Isolates

Transfer immutable configuration, messages, and validated W3C trace context.
For ObjectBox, transfer reference bytes and attach a new Store wrapper in the
receiving isolate; close it in `finally`.

`IsolateWorker` protocol version 2 uses a monotonic correlation nonce local to
one worker generation. The caller-facing request ID is never the wire identity,
so reusing it after a terminal cannot let a stale envelope complete newer work.
ACK and result Futures may be awaited independently. Payload/result/failure DTOs
must be versioned and transferable; their isolate copy cost remains part of the
consumer workload. Cooperative cancellation is preferred, while `safeStop`
keeps a bounded force-kill deadline for non-cooperative handlers.

Projection stays `ProjectionExecution.inline` unless composition explicitly
injects a `ProjectionExecutor`. `IsolateProjectionExecutor` creates one worker
per task and accepts only transferable callback/request/result values. A
cancelled or superseded generation cannot publish, but the worker is allowed to
finish its isolate-local `finally`; dispose the executor to drain worker exits.

For ObjectBox, `ObjectBoxProjectionExecutor` borrows the original Store and uses
`Store.runAsync`, whose callback receives its own attached Store wrapper. Create
and close every query and background graph inside that callback. Dispose the
collection first, then the executor, then close the original Store. Never send
a `Store`, query, owner, client, or closure capturing one across the boundary.

## Review checklist

- The composition root is visible and testable.
- Every value is classified as owned, borrowed, or transaction-transferred.
- Data is classified as ephemeral, temporary, or persisted.
- Providers are registered before dependents, producing reverse teardown.
- Every background entrypoint builds and tears down its graph.
- Background projection is explicit, generation-guarded, and fully drained.
- Unexpected exceptions are rethrown after optional reporting.
