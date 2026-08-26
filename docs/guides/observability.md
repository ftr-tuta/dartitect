# Observability

[Português (Brasil)](observability.pt-BR.md)

## Safe defaults

Create `ObservabilityRuntime` explicitly. Developer logging is the default;
remote reporting/tracing require an explicit provider at composition. Never use
global telemetry objects.

## Data policy

Sanitize before every destination. Do not record authorization, cookies,
tokens, passwords, bodies, headers, query strings, DSNs, identity, or identifying
paths. Errors and fatal events are not sampled away. Destination failures stay
isolated from application behavior.

## Tracing

Accept only valid W3C `traceparent`; forward optional `tracestate`; baggage is
off by default. End every span exactly once in `finally`. Transfer only validated
context between isolates.

## Errors

Expected `Err<F>` values remain command state. Unexpected crashes may be
reported once with a sanitized mechanism, handled state, fingerprint, and
attributes, then rethrown.

## Payload-free reactive events

`ReactiveOwner` and `MutationCommand` can emit `ReactiveChangeEvent` values to
an injected `ReactiveObserver`. Events contain only a fixed source/kind, an
exact `ChangeCause` identity registered at composition, monotonic revisions,
monotonic duration, and listener count. They never contain domain values,
entity or idempotency keys, error messages, stack traces, or user identity.

Use `ReactiveJournal` only as an opt-in, memory-only diagnostic ring. Its
default capacity is 200, old entries are overwritten, and disposal clears the
ring permanently. Declare ownership explicitly when registering it. A failing
observer is reported once, disabled, and cannot change runtime state or the
exception seen by the caller.

```dart
final journal = ReactiveJournal();
final owner = ReactiveOwner(
  observer: ReactiveObserverRegistration.owned(
    journal,
    dispose: journal.dispose,
  ),
);
```

For a telemetry destination, inject `ReactiveObserverLoggerAdapter` instead.
It emits only the fixed `reactive.change` message and allowlisted facts through
`ObservabilityRuntime`; normal redaction then runs again before every sink. A
Sentry integration is the same chain ending in `SentryLogSink`, whose Hub stays
borrowed. There is no persistence or network destination by default.

## Flutter and providers

Install one `FlutterErrorBinding`, chain/restore prior handlers, and prevent
recursion. Sentry adapters borrow a consumer-initialized Hub and never configure
or close it.
