# dartitect_observability

## Purpose

Provider-neutral structured logging, error reporting, W3C trace propagation,
redaction, sampling, bounded dispatch, and explicit runtime ownership. Local
developer logging is the safe default; remote destinations are opt-in.

## When to use

Use it when application and infrastructure code need stable telemetry contracts
without depending on a vendor SDK, and when redaction/ownership/failure
isolation must be enforced at composition.

## When not to use

Do not use it as a collector, backend, secret store, consent system, or provider
initializer. Do not add a remote destination without an explicit data,
retention, consent, and ownership policy.

## Platforms and entrypoints

Import
`package:dartitect_observability/dartitect_observability.dart`. It is pure Dart
and supports the Dart VM, Flutter, and web. Provider adapters may support a
narrower platform set.

## Mental model and data flow

Producers emit provider-neutral logs, unexpected-error events, and spans into an
`ObservabilityRuntime` created at a visible composition root. The runtime applies
allowlisting, redaction, sampling, bounded dispatch, and destination isolation.
Each provider adapter is registered as owned or borrowed explicitly.

Expected application failures stay in `Result`/command/resource state. Only
unexpected crashes cross the error-reporting boundary. Trace context uses
validated W3C fields and transfers as data, never as a global SDK object.

## Minimal workflow

```dart
import 'package:dartitect_observability/dartitect_observability.dart';

Future<void> main() async {
  final runtime = ObservabilityRuntime();
  try {
    runtime.logger.info('Application started.');
  } finally {
    await runtime.disposeAsync();
  }
}
```

The default destination is local developer logging. Register remote sinks,
reporters, or tracers only at composition after policy review.

## Public API tour

- `ObservabilityRuntime` owns registrations and coordinates bounded dispatch,
  flush, and disposal.
- `DartitectLogger`, `LogEvent`, `LogSink`, `DeveloperLogSink`,
  `CallbackLogSink`, filters, lazy messages, and registration types define logs.
- `ErrorReporter`, `ErrorEvent`, severities/mechanisms, callback/no-op reporters,
  and `RedactedError` define unexpected error reporting.
- `Tracer`, `Span`, `TraceContext`, `TracePropagator`,
  `W3CTracePropagator`, trace ID generators, kinds, and statuses define tracing.
- `Redactor`/`RedactionLimits` and `SamplingPolicy` implementations enforce data
  and volume policy.
- `ArchitectureObserverBridge` and `ReactiveObserverLoggerAdapter` map fixed
  payload-free architecture/reactive facts into the runtime.
- `ObservabilityContext`, event names, and diagnostics provide fixed
  correlation/health facts without domain payloads.

## Ownership and lifecycle

Create one runtime per app, session, or isolate graph. Stop producers and Flutter
bindings first, then flush and dispose the runtime, then close any
consumer-owned provider SDK. Registrations state whether a sink is owned or
borrowed; a borrowed provider object is never closed by Dartitect.

Build a new runtime inside a receiving isolate and transfer only validated trace
context. Do not transfer a provider Hub/client or the runtime itself.

## Failure, cancellation, and concurrency

Destination failure is isolated from application behavior and from other
destinations. Reporting and logging callbacks cannot replace the original
exception. Errors and fatal events are never sampled away. End every span
exactly once, preferably in `finally`.

Dispatch and retained diagnostics are bounded. Disposal closes admission,
drains/flushes owned destinations, and aggregates cleanup failures. This package
does not cancel application work; request/resource cancellation remains owned by
the calling boundary.

## Prohibited uses and limitations

Never record authorization, cookies, tokens, passwords, request/response bodies,
headers, query strings, DSNs, user identity, entity/idempotency keys, or
identifying paths. Do not duplicate capture through global handlers, Dio
interceptors, and provider auto-instrumentation. Do not let telemetry failure or
sampling change an application result.

The package provides contracts and local behavior, not storage, export,
dashboards, alerting, or legal compliance.

## Testing

Run `dart test`. Use recording fakes from `dartitect_testing` to verify
redaction, allowlists, sampling, overflow, sink isolation, reentrancy, W3C
validation, exact-once span end, flush/disposal order, and absence of sensitive
attributes.

## Related packages and guides

Use `dartitect_dio` for minimal HTTP integration, `dartitect_sentry` for a
borrowed Sentry Hub, and `dartitect_testing` for recording destinations. Read
[observability](../../docs/guides/observability.md),
[adapters](../../docs/guides/adapters.md), and
[custom integrations](../../docs/guides/custom-integrations.md).

## Availability

The workspace contains the `1.0.0-rc.8` source candidate. Use only coordinates
from a matching tag with a published GitHub Release and one compatible cohort.
If no compatible Release exists, there is no supported consumption path. See
the [Git candidate consumption guide](../../docs/guides/git-candidate-consumption.md).
