# Dio adapter

Create `DioOwner` or borrow an injected Dio instance in infrastructure. Map
cancellation, transport, HTTP, and configuration failures distinctly. Preserve
the caller's cancellation and concurrency semantics.

Generated OpenAPI operation wrappers receive `DioJsonClient`, never raw `Dio`,
and inherit cancellation, deadline, credentials, and observability from the
selected transport context. Only operations declared by the feature enter its
graph. Keep status semantics, DTO/domain mapping, retry, authentication, and
idempotency policy consumer-owned.

Credential requests carry `CredentialGeneration` in Dio request extras. Bind
waiting to `CancelToken`, invalidate only that generation, and deduplicate
concurrent 401 logout. Authenticated replay stays disabled unless the consumer
supplies both a retry client and an explicit semantic idempotency policy. Permit
at most one replay and never repeat streams or multipart/upload bodies.

Use `DioObservabilityCapturePolicy.metadataOnly()` by default for fixed
method/protocol/status/error-type facts and zero payload. Diagnostic capture is
explicit, requires classifications, and accepts only already-materialized
JSON-safe structures; never consume streams, multipart values, bytes, or files.
Remove `LogInterceptor`, propagate only through the configured W3C propagator,
and reject duplicate Dartitect/`sentry_dio` capture. Test with Dio's real
interceptor/adapter boundary and deterministic no-network responses. Dispose an
owned Dio only after requests and instrumentation drain.
