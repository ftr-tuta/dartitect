# dartitect_resilience

## Purpose

Pure-Dart, provider-neutral resilience primitives with explicit bounds,
failure classification, time budgets, cancellation, and injectable execution
dependencies. The package depends only on `dartitect`.

## When to use

Use it for a bounded retry, single-flight operation, circuit breaker, bulkhead,
or rate limiter when those policies must be visible at composition.

## When not to use

Do not use it to invent a universal failure taxonomy or to hide retry inside a
repository. It parses optional HTTP retry feedback but leaves status semantics, auth,
scheduling, storage, and idempotency to the consumer.

## Platforms and entrypoints

Import `package:dartitect_resilience/dartitect_resilience.dart`. It is pure Dart
and supports the Dart VM, Flutter, and web.

## Mental model and data flow

The consumer classifies an expected typed failure. `RetryExecutor` applies an
explicit attempt, elapsed-time, backoff, jitter, cancellation, and deadline
budget. Unexpected exceptions remain crashes. An uncertain result stops
automatic retry.

## Minimal workflow

```dart
final result = await RetryExecutor().execute<int, MyFailure>(
  operation: runAttempt,
  policy: RetryPolicy(
    classify: (failure) => failure.transient
        ? const RetryDecision.retry()
        : const RetryDecision.stop(),
  ),
  cancellation: cancellation,
);
```

## Public API tour

`RetryPolicy`, `RetryDecision`, backoff, and jitter define retry behavior.
`SingleFlight` shares matching work without sharing waiter cancellation.
`CircuitBreaker`, `Bulkhead`, and `RateLimiter` bound admission and retention.
Clock, scheduler, and randomness interfaces support deterministic evidence.
`RetryAfterParser` distinguishes absent, valid, invalid, and excessive feedback.
`RetryBudget` shares attempt, elapsed, bulkhead, and rate admission across
consumer operations. See [HTTP retry budgets](../../docs/guides/http-retry-feedback.md).

## Ownership and lifecycle

The composition root owns long-lived coordination primitives and disposes them
before their clients/providers. Borrowed operations retain their own resources.
Closing single-flight cancels shared work; cancelling one waiter only detaches
that waiter unless no waiters remain.

## Failure, cancellation, and concurrency

Expected failures remain `Result<T, F>`. Cancellation and deadline exceptions
are control flow; programming defects escape. Every queue, concurrent count,
failure window, and retained key is positively bounded.

## Prohibited uses and limitations

- No retry of uncertain mutations.
- No unbounded queue, key registry, or failure history.
- No inferred idempotency or exactly-once claim.
- No conversion of an unexpected exception to an expected failure.

## Testing

Run `dart test`. Inject deterministic clocks, schedulers, and randomness. Cover
budgets, cancellation, uncertainty, owner disposal, waiter detachment, open/
half-open breaker behavior, overflow, and zero retained state.

## Related packages and guides

Use `dartitect_sync` for durable mutation policy and `dartitect_jobs` for
headless execution. Read the
[paved-road guide](../../docs/guides/paved-road-platform.md).

## Availability

Dartitect `1.1.0` is distributed only by the annotated `v1.1.0` tag and
its immutable GitHub Release. Declare this package directly with the canonical
Git descriptor; its transitive Dartitect dependencies resolve from the same tag
without overrides. See the
[Git release consumption guide](../../docs/guides/git-release-consumption.md).
