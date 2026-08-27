# Runtime and reactive tests

Cover `Ok`, `Err`, unexpected rethrow with original stack, every bounded command
policy, disposed terminal state, `start` once, owned/borrowed hosts, effects
before/after listener, FIFO/overflow/second consumer, forced logout after route
removal, and reverse disposal.

For reactive work, cover hot/warm/cold transitions, activation-local sessions,
backpressure, retry after crash, exact-revision refresh, family sharing and
eviction, atomic collection failure, tombstone expiry, background projection
staleness, selector equality, debounce cancellation, TickerMode pause,
payload-free rebuild diagnostics, and localized Material semantics. End with no
listeners, timers, effects, sessions, source sessions, family leases,
projection workers, or graph edges.

For `DerivedAsyncResource`, use an old loader that deliberately ignores
cancellation and prove it cannot publish over a newer dependency generation.
Verify activation-local dependency listener counts, each stale-data policy,
deduplication, family key/eviction ownership, and terminal cleanup. For
diagnostics, feed only protocol events to `DiagnosticsTopologyHarness`, cover
all fixed subject categories, ordering violations, off semantics, reporter
failure isolation, bounded overflow, and zero retained events after disposal.
