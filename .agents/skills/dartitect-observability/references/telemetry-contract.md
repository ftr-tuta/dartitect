# Telemetry contract

Accept only valid W3C `traceparent`. Validate `tracestate` under its own policy;
never convert it into an attribute, tag, or baggage item. Keep baggage off by
default. Transfer only validated context between isolates. End operation spans
exactly once in `finally`.

Expected `Err<F>` remains command state and is not automatically reported.
Unexpected crashes may be reported once with sanitized mechanism, handled state,
fingerprint, and allowlisted attributes, then are rethrown with the original
stack. Errors and fatal events bypass sampling. Every destination has
independent sampling and a bounded queue containing only private-constructor
prepared events, with explicit overflow behavior. It never stores a closure
retaining raw input. One destination failure cannot affect the application or
another destination. `flushDetailed` reports outcomes by destination while
compatible `flush(Duration)` remains available.

Diagnostics protocol v2 permits only fixed enums, opaque process-local IDs,
counters, generations, revisions, and monotonic time. It rejects metadata,
URLs, domain keys, dynamic errors, stacks, and user identifiers. Optional
Diagnostics-v2 DevTools registration is explicit, isolate-local,
development-only, and exposes exactly capabilities, snapshot, and event-delta
reads; disposal clears the ring. The separate
`ext.dartitect.observabilityPrivacy` RPC exposes only profile, effective actions,
queue/failure counts, and sanitizer counts—never values, samples, or reasons.
