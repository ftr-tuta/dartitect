# Lifecycle and live resources

Nested `ReactiveOwner.update` calls join the outer transaction; listeners run
only after affected computed values stabilize. A compute crash preserves the
prior graph snapshot, is reported through the injected reporter, and is
rethrown. Disposal removes every edge and listener.

`LiveResource<T, F>` separates waiting/ready/failed/crashed data from hot/warm/
cold temperature. A hot resource owns an active source session, warm retains
last-known data without upstream activity, and cold discards both. Use an
`AsyncLifecycleBarrier` so disposal closes admission, cancels cooperatively,
drains admitted work, and rejects stale publication.

Select `RemoteRefresh`, `LocalCommitRefresh`, or `ObservedLocalRefresh` according
to the completion the caller needs. Observed refresh waits for the exact typed
revision and requires a positive timeout mapped explicitly to `F`.
