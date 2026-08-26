# Dio adapter

Create `DioOwner` or borrow an injected Dio instance in infrastructure. Map
cancellation, transport, HTTP, and configuration failures distinctly. Preserve
the caller's cancellation and concurrency semantics.

Record only allowlisted method/protocol/status facts—never body, headers, query,
credentials, or identifying path. Propagate only through the configured W3C
propagator. Reject duplicate tracing/capture between Dartitect and `sentry_dio`.
Test with Dio's real interceptor/adapter boundary and deterministic no-network
responses. Dispose an owned Dio only after requests and instrumentation drain.
