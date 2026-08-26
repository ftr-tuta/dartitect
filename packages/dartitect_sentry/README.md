# dartitect_sentry

[Português (Brasil)](README.pt-BR.md)

## Purpose

Adapters from Dartitect logs, errors, and spans to an injected Sentry `Hub`.
The consumer initializes, configures, and closes Sentry.

## When to use it

Use it only after the application has explicitly selected and initialized
Sentry. It is not an initialization wrapper and never supplies a DSN.

## When not to use it

Do not use it before consumer initialization/consent, as a source of provider-
neutral contracts, or alongside duplicate Flutter, Dio, or tracing capture.

## Recommended combinations

Combine with `dartitect_observability`; inject a borrowed Hub and dispose all
Dartitect sinks/reporters/tracers before the consumer closes it. See the
[ecosystem selection guide](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/ecosystem-selection.md)
and [implementation recipes](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/implementation-recipes.md).

## Install

This candidate is not published on pub.dev. Declare
`dartitect_sentry: 1.0.0-rc.1` and use the
[Git candidate consumption guide](../../docs/guides/git-candidate-consumption.md)
to generate the complete override closure.

## Minimal example

```dart
// The consumer initializes Sentry and owns this Hub.
final sink = SentryLogSink(hub: hub);
final runtime = ObservabilityRuntime(sinks: [LogSinkRegistration.borrowed(sink)]);
await runtime.disposeAsync(); // Does not close hub.
```

The packaged example uses no network and no real DSN.

## Public API tour

- `SentryLogSink` maps sanitized logs to breadcrumbs/events.
- `SentryErrorReporter` maps unexpected errors with explicit mechanism state.
- `SentryTracer` maps spans while preserving provider-neutral contracts.

Reactive events reach Sentry only through `ReactiveObserverLoggerAdapter`, an
`ObservabilityRuntime`, and `SentryLogSink`. This keeps the event payload-free
and applies redaction at both the observer mapping and destination boundary.

## Ownership

All adapters borrow the Hub. The consumer initializes/configures/closes it after
Dartitect producers and observability resources have stopped and flushed.

## Limitations

Never duplicate capture with global handlers or `sentry_dio`. Redaction occurs
before the Hub; bodies, headers, queries, credentials, DSNs, and identity are
not accepted as telemetry attributes.

## Extending

Keep Sentry-specific mapping in this isolated package. Custom providers should
implement the neutral contracts rather than depend on these adapters.

## Testing

Run `dart test`. Tests use a fake Hub, zero network, sanitized mapping,
exact-once span end, and borrowed-lifetime assertions.

## Links

See [observability](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/observability.md),
[adapters](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/adapters.md), and the [issue tracker](https://github.com/ftr-tuta/dartitect/issues).
