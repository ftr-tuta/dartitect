# Changelog

## 1.0.0-rc.1

- Assemble the reviewed lockstep 1.0 release candidate and freeze internal
  dependencies at `>=1.0.0-rc.1 <1.0.0`.

- Restrict internal Dartitect dependencies to the exact lockstep 1.0
  prerelease series.

- Add idempotent `FirstFrameGate` ownership for failure-safe bootstrap release.
- Add pure sealed presentation projections for local-authority
  `ResourceSnapshot` states with distinct typed failure and crash causes.
- Add ticker-aware headless reactive/resource/collection/paged builders plus
  opt-in accessible Material resource and paged-list views with granular keyed
  item rebuilds and route-owned effects.
- Add opt-in background `LiveCollection` projection with transferable keyed
  inputs/outputs, exact inline parity, cancellation, and generation guards.
- Add sanitized causal events to outer `ReactiveOwner` updates with monotonic
  revisions, duration, listener counts, crash events, and isolated observers.
- Add headless equality-aware selectors, owned debounced values, and local-first
  paged resources with typed cursors, causal write receipts, stable-key page
  deduplication, and explicit join/drop/restart-latest command lanes.
- Add `LiveCollection` with explicit replace/diff/versioned projection modes,
  item-specific listenables, atomic structural changes, and bounded tombstones.
- Add owned `ResourceFamily` caches with explicit keyed leases, TTL,
  deterministic recreation-cost/LRU eviction, weighted idle limits, and
  family-owned prewarming.
- Add owner-bound typed invalidation groups, hot/warm/cold stale semantics,
  local commit receipts, observed values, and bounded causal refresh waits.
- Add `LiveResource`, activation-local `ReactiveSource` sessions, four bounded
  backpressure policies, typed failures, explicit crash retry, and stale
  publication rejection.
- Add orthogonal resource data/temperature state, ticker-aware observations,
  warm TTL policies, explicit leases, and an asynchronous drain barrier.
- Add the opt-in owned reactive graph with atomic batching, typed sharing,
  topological recomputation, rollback, and deterministic teardown.
- Prepare opt-in reactive and Material entrypoints without changing the
  established thin Flutter library.
- Initial Flutter lifecycle and reactivity primitives.
