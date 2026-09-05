# HTTP retry feedback and shared admission

The prepared 1.2.0 source adds optional feedback handling to
`dartitect_resilience`, `dartitect_dio`, and `MutationCommand`. Existing callers
keep their retry defaults. Transport, status semantics, authentication,
idempotency, reconciliation, and scheduling remain consumer-owned.

## Parse feedback at receipt

`RetryAfterParser` implements seconds and all three HTTP-date formats from
[RFC 9110](https://www.rfc-editor.org/rfc/rfc9110.html#section-10.2.3).
Supply `maximumDelay`, `maximumFieldBytes`, and the UTC receipt time. Field
length and ASCII validity are checked before copying or parsing. Decimal
seconds are checked against the limit before multiplication, including on web.

The returned `RetryAfterHint` retains only a classification and, for valid
feedback, a non-negative minimum duration. Absence differs from malformed or
excessive feedback. Past dates produce zero. Excessive delays are never
clamped. The injected receipt clock owns synchronization and any known clock
offset; the parser never guesses a correction from another header. RFC 850
two-digit years use the 50-year interpretation rule.

At a Dio boundary, supply `DioRetryAfterPolicy` to `DefaultDioJsonClient` or
`captureDioException`. Only `DioHttpFailure.retryAfter` retains the typed result.
Duplicate field lines are invalid. No raw header, URI, credential, or response
body enters feedback metadata. The adapter makes one request per execution.

## Compose one retry owner

The consumer selects retryable failures and distinguishes definitive failures
from uncertainty. A timeout after sending a mutation can require
`RetryDecision.uncertain()` even when a server hint exists.

```dart
final policy = RetryPolicy<MyFailure>(
  maxAttempts: 3,
  maxElapsed: const Duration(seconds: 30),
  jitter: const FullJitter(),
  classify: (failure) => failure.uncertain
      ? const RetryDecision.uncertain()
      : failure.transient
      ? RetryDecision.retry(retryAfter: failure.retryAfter)
      : const RetryDecision.stop(),
);
```

The effective delay is `max(jitteredBackoff, validServerMinimum)`. Invalid and
excessive hints stop automatic retry. A valid minimum that does not fit the
remaining budget returns the last typed failure for consumer deferral. The
minimum is measured from receipt; composing later may conservatively wait
longer. Cancellation remains cooperative control flow. Unexpected exceptions
retain their original stack and are never automatically classified.

## Share admission across operations

Create a finite budget when a bootstrap or reconnect window starts, before
queueing work. Borrow one `Bulkhead` and one `RateLimiter` from the composition
root. Pass the same budget to `RetryExecutor.execute(budget: ...)` at each
participating leaf operation. A leaf operation performs exactly one transport
attempt. Keep retries at this layer: wrapping another retry loop consumes extra
attempts and can queue recursively behind its own bulkhead admission.

```dart
final bulkhead = Bulkhead(maxConcurrent: 2, maxQueue: 4);
final budget = RetryBudget(
  maxAttempts: 12,
  maxElapsed: const Duration(seconds: 30),
  bulkhead: bulkhead,
  rateLimiter: RateLimiter(
    capacity: 6,
    refillTokens: 2,
    refillPeriod: const Duration(seconds: 1),
    clock: clock,
  ),
  clock: clock,
);
```

Use the budget in the repository operation invoked by refresh, the connection
attempt invoked by reconnect, and page fetches invoked by `SyncDataset` and
`HeadlessSyncEndpoint`. These owners continue to control publication,
generation, checkpoint confirmation, and lifecycle. Page and retained-item
limits remain separate from the attempt budget. A background isolate creates
its own graph and budget from configuration; objects never cross isolates.
Cross-process admission requires a consumer-owned durable authority.

Queue wait, attempt time, and inter-attempt waits count against elapsed bounds.
Cancellation, deadline, elapsed time, and shared admission are checked again
after queueing, immediately before execution. Rate denial is immediate. An
initial denial raises `RetryBudgetExceededException`; a denial after a typed
failure returns that failure. A full bulkhead raises
`BulkheadRejectedException`. Clock regression stops work conservatively.
These bounds prevent new execution; an already-running operation must honor
the supplied cancellation and transport deadline.

## Preserve durable outbox state

Pass the borrowed budget as `MutationCommand(retryBudget: budget, ...)` and
feedback as `MutationFailurePolicy.queued(retryAfter: hint, retry: ...)`.
The command is the retry owner; its `synchronize` callback makes one attempt.
Deferral preserves the local change, pending state, and idempotency identity.
Uncertain operations retain identity and require explicit reconciliation before
delivery. No feedback automatically rolls back local data or changes conflicts.

Dispose commands and other borrowers, then dispose the bulkhead and transport
providers in dependency order. `RetryBudget` owns no queue, timer, subscription,
or client. It never replenishes consumed attempt tokens; create another scope
only when consumer scheduling explicitly admits a new window.

## Verification and compatibility limits

Deterministic VM and Chrome tests cover numeric bounds, HTTP dates, skew,
malformed/excessive feedback, jitter, overflow, cancellation, queue deadlines,
elapsed exhaustion, shared attempt caps, and residual-resource cleanup. Dio
tests use the real provider adapter boundary without network requests. Outbox
tests verify identity and pending-state preservation on admission refusal.

These tests establish local retry composition. Paired Python protocol and
persistent recovery acceptance additionally require the integrated, immutable
Pytitect reference and shared bundles specified by issues #26 and #28.
