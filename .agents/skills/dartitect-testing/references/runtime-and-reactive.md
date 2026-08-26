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
