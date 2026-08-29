# dartitect_sentry

## Purpose

Adapters from Dartitect's provider-neutral logs, unexpected errors, and spans
to an injected Sentry `Hub`. The consumer initializes, configures, consents to,
flushes, and closes Sentry.

## When to use

Use it only after the application has explicitly selected and initialized
Sentry and has a reviewed telemetry/redaction policy.

## When not to use

Do not use it as a Sentry initializer, DSN source, consent system, or source of
provider-neutral contracts. Do not use it alongside duplicate Flutter, Dio, or
tracing capture for the same events.

## Platforms and entrypoints

Import `package:dartitect_sentry/dartitect_sentry.dart`. It supports the Dart and
Flutter platforms supported by the pinned Sentry SDK and the consumer's
configuration.

## Mental model and data flow

The application creates a Sentry Hub. At composition, Dartitect adapters borrow
that Hub and are registered with `ObservabilityRuntime`. Application facts pass
through neutral contracts, redaction, and runtime policy before reaching the
adapter. The adapter maps the sanitized event to Sentry and never takes Hub
ownership.

## Minimal workflow

```dart
import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:dartitect_sentry/dartitect_sentry.dart';
import 'package:sentry/sentry.dart';

Future<void> attach(Hub consumerOwnedHub) async {
  final sink = SentryLogSink(hub: consumerOwnedHub);
  final runtime = ObservabilityRuntime(
    sinks: <LogSinkRegistration>[LogSinkRegistration.borrowed(sink)],
  );
  await runtime.disposeAsync(); // Does not close the Hub.
}
```

The packaged example uses no DSN and performs no network request.

## Public API tour

- `SentryLogSink` maps sanitized logs to appropriate Sentry breadcrumbs/events.
- `SentryErrorReporter` maps unexpected errors with explicit mechanism and
  handled state.
- `SentryTracer` maps provider-neutral spans and status to Sentry spans.

Payload-free reactive events reach Sentry only through
`ReactiveObserverLoggerAdapter`, `ObservabilityRuntime`, and `SentryLogSink`.

## Ownership and lifecycle

Every adapter borrows the injected Hub. Stop application producers and Flutter/
Dio bindings, dispose or flush Dartitect adapters/runtime, and only then close
the consumer-owned Hub. Recreate the Hub and adapters inside each isolate; never
transfer either live object.

## Failure, cancellation, and concurrency

Provider failures remain isolated by the observability runtime and cannot
replace application outcomes. End spans exactly once. Cancellation is recorded
only through reviewed safe mechanism/status data; this package does not cancel
application work. The Sentry SDK owns provider concurrency while Dartitect
runtime bounds and drains its own dispatch.

## Prohibited uses and limitations

- No SDK initialization, DSN, release/environment selection, consent, or Hub
  closure.
- No duplicate global, Flutter, Dio/`sentry_dio`, error, or trace capture.
- No bodies, headers, queries, credentials, DSNs, identity, entity keys, or
  identifying paths.
- No network-dependent package example or test.

## Testing

Run `dart test`. Use a fake Hub and zero network. Verify sanitized mapping,
handled/mechanism state, breadcrumb/event selection, exact-once span end,
provider failure isolation, and borrowed lifetime.

## Related packages and guides

Requires `dartitect_observability` for neutral contracts. `dartitect_dio` can
provide HTTP facts only when duplicate Sentry capture is disabled. Read
[observability](../../docs/guides/observability.md) and
[adapters](../../docs/guides/adapters.md).

## Availability

The workspace contains the `1.0.0-rc.8` source candidate. Use only coordinates
from a matching tag with a corresponding published GitHub Release and its
complete cohort notes. Without one, there is no supported consumption path. See
the [Git candidate consumption guide](../../docs/guides/git-candidate-consumption.md).
