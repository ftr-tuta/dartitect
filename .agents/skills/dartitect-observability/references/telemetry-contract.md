# Telemetry contract

Accept only valid W3C `traceparent`, forward optional `tracestate`, and keep
baggage off by default. Transfer only validated context between isolates. End
operation spans exactly once in `finally`.

Expected `Err<F>` remains command state and is not automatically reported.
Unexpected crashes may be reported once with sanitized mechanism, handled state,
fingerprint, and allowlisted attributes, then are rethrown with the original
stack. Errors and fatal events bypass sampling. Bounded destination queues must
have explicit overflow behavior, and one destination failure cannot affect the
application or another destination.
