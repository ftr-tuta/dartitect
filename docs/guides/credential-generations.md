# Credential generations and authenticated requests

`CredentialsController<C, F>` publishes `CredentialLease<C>` values. Each
lease carries an opaque `CredentialGeneration` that must accompany work using
that credential. A late provider response may invalidate only the exact
generation it used:

```dart
final loaded = await credentials.load(cancellation: cancellation);
switch (loaded) {
  case Ok(:final value):
    final lease = value;
    await send(lease.value, lease.generation);
  case Err(:final failure):
    handleExpectedCredentialFailure(failure);
}

await credentials.invalidateIfCurrent(
  generationFromRequest,
  CredentialInvalidationCause.providerRejected,
);
```

Acquisition is single-flight, but waiter cancellation is independent. One
cancelled route/request stops waiting without cancelling refresh or persistence
needed by another waiter. Invalidation advances the internal revision first,
cancels and drains acquisition, and only then clears the store. A delayed write
therefore cannot restore credentials after logout, even when a consumer store
ignores cooperative cancellation during its write. Forced logout is shared for
concurrent invalidations of the same generation.

`DioCredentialsInterceptor` records the generation in `RequestOptions.extra`
and races credential acquisition against the request's `CancelToken`. A 401
from an old request calls `invalidateIfCurrent` and cannot clear a newer lease.
The authorization header value is never retained by Dartitect after the
request is forwarded.

Authenticated replay is disabled by default. To permit one retry, provide both
a borrowed `retryClient` and a consumer implementation of
`DioCredentialReplayPolicy` that makes the endpoint's semantic idempotency
decision. The interceptor fences replay count to one. Streams, `FormData`, and
`MultipartFile` bodies are never replayed, even when the policy returns true.
There is no default based on HTTP method and no hidden retry/backoff.

Test at least individual waiter cancellation, refresh/logout overlap, delayed
persistence, concurrent 401 responses, a delayed old 401, disposal during
refresh, denied replay, one allowed replay, and stream/upload rejection with a
deterministic adapter and no network.
