# dartitect_observability

[Português (Brasil)](README.pt-BR.md)

## Purpose

Provider-neutral structured logging, error reporting, W3C tracing, redaction,
sampling, bounded dispatch, and runtime ownership. Local developer logging is
the safe default; remote destinations are opt-in.

## When to use it

Use it when application code needs stable telemetry contracts without owning a
vendor SDK. It is not a collector, backend, exporter, or secret store.

## When not to use it

Do not add remote destinations without an explicit data, consent, and ownership
policy. Do not use it to initialize provider SDKs or record credentials and
domain payloads.

## Recommended combinations

Combine with core/runtime packages through injected logger, reporter, and tracer
contracts. Add `dartitect_sentry` only for a consumer-initialized Sentry Hub and
keep other providers behind custom adapters. See the
[ecosystem selection guide](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/ecosystem-selection.md)
and [implementation recipes](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/implementation-recipes.md).

## Install

This candidate is not published on pub.dev. Declare
`dartitect_observability: 1.0.0-rc.4` and use the
[Git candidate consumption guide](../../docs/guides/git-candidate-consumption.md)
to generate the complete override closure.

## Minimal example

```dart
final runtime = ObservabilityRuntime();
runtime.logger.info('Application started.');
await runtime.disposeAsync();
```

## Public API tour

- `ObservabilityRuntime` owns registered sinks and coordinates flush/disposal.
- `DartitectLogger`, `LogEvent`, `LogSink`, and `CallbackLogSink` define logs.
- `ErrorReporter`, `ErrorEvent`, and no-op/callback implementations define errors.
- `Tracer`, `Span`, `TraceContext`, and `W3CTracePropagator` define tracing.
- `Redactor`, `SamplingPolicy`, and `ObservabilityDiagnostics` enforce policy.
- `ArchitectureObserverBridge` maps architecture signals without coupling core.
- `ReactiveObserverLoggerAdapter` maps payload-free reactive events to a fixed
  message and allowlisted attributes. The runtime redacts them again before any
  local or Sentry destination.

## Ownership

Create one runtime per app/session/isolate composition root. Dispose producer
bindings first, then flush/dispose owned sinks, reporters, and tracers. Provider
objects can remain borrowed and consumer-owned.

## Limitations

Never record authorization, cookies, tokens, passwords, bodies, headers,
queries, DSNs, identity, or identifying paths. Destination failures are isolated;
errors/fatal events are never sampled away.

## Extending

Implement `LogSink`, `ErrorReporter`, or `Tracer`; sanitize before the provider.
See the custom integration guide for dependency and ownership requirements.

## Testing

Run `dart test`. Use recording fakes from `dartitect_testing`; assert redaction,
overflow, sink isolation, exact-once span end, and flush/disposal order.

## Links

See [observability](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/observability.md),
[custom integrations](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/custom-integrations.md), and the [issue tracker](https://github.com/ftr-tuta/dartitect/issues).
