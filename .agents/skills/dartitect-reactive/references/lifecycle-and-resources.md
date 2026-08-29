# Lifecycle and live resources

Nested `ReactiveOwner.update` calls join the outer transaction; listeners run
only after affected computed values stabilize. A compute crash preserves the
prior graph snapshot, is reported through the injected reporter, and is
rethrown. Disposal removes every edge and listener.

`ReactiveLazyComputed<T>` declares dependencies explicitly, evaluates on first
read or observation, marks dirty while unobserved, and recomputes atomically
while observed. A compute failure preserves its last valid value and remains
dirty. Hot reload uses explicit `rebind`; never add ambient read tracking.

`LiveResource<T, F>` separates waiting/ready/failed/crashed data from hot/warm/
cold temperature. A hot resource owns an active source session, warm retains
last-known data without upstream activity, and cold discards both. Use an
`AsyncLifecycleBarrier` so disposal closes admission, cancels cooperatively,
drains admitted work, and rejects stale publication.

`DerivedAsyncResource<T, F>` is stable and accepts a non-empty, identity-unique
list of explicit Flutter `Listenable` dependencies. It uses
restart-latest cancellation plus dependency and lifecycle generation guards;
an old non-cooperative result never publishes. Select preserve, discard, or
stale-while-revalidate last-data policy and explicit equality. It wraps one
`LiveResource`; return `.liveResource` from an existing `ResourceFamily`
factory so typed key, leases, TTL, count/weight limits, and eviction remain
family-owned. Do not add implicit read tracking or replace global hooks.

Select `RemoteRefresh`, `LocalCommitRefresh`, or `ObservedLocalRefresh` according
to the completion the caller needs. Observed refresh waits for the exact typed
revision and requires a positive timeout mapped explicitly to `F`.
