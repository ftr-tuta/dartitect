# dartitect_dio

[Português (Brasil)](README.pt-BR.md)

## Purpose

Optional ownership, typed failure, cancellation, W3C propagation, and minimal
telemetry helpers around the real Dio API.

## When to use it

Use it at an infrastructure composition root that already chose Dio. Do not
import Dio or this adapter into domain, ViewModel, or presentation code.

## When not to use it

Do not use it when the application has not selected Dio, when a domain-facing
HTTP abstraction is expected, or when another interceptor already provides the
same tracing/capture.

## Recommended combinations

Combine with application-owned transport contracts, `dartitect_observability`
for neutral telemetry policy, and offline-first repositories only after their
local transaction boundary is defined. See the
[ecosystem selection guide](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/ecosystem-selection.md)
and [implementation recipes](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/implementation-recipes.md).

## Install

This candidate is not published on pub.dev. Declare
`dartitect_dio: 1.0.0-rc.3` and use the
[Git candidate consumption guide](../../docs/guides/git-candidate-consumption.md)
to generate the complete override closure.

## Minimal example

```dart
final owner = DioOwner.create();
try {
  final response = await owner.dio.get<void>('/health');
  print(response.statusCode);
} finally {
  owner.dispose();
}
```

## Public API tour

- `DioOwner.create` owns/closes a client; `DioOwner.value` borrows one.
- `DioFailure` variants separate cancellation, HTTP, transport, and config.
- `captureDioException` maps Dio exceptions to typed `Result` failures.
- `DartitectHeadersInterceptor` propagates only configured W3C context.
- `DioTelemetryInterceptor`/`DioInstrumentation` emit minimal safe attributes.
- `ownCancelToken` registers cooperative cancellation with a `ResourceOwner`.
- `bindCancelToken` binds a pure-Dart `CancellationSignal` to one shareable
  Dio token without reversing ownership.

## Ownership

Create the client at an app/session/isolate composition root. Dispose requests
and cancellation tokens before an owned Dio client. Borrowed clients are closed
by their consumer owner.

## Limitations

Telemetry includes method, protocol, and status only—never bodies, headers,
queries, credentials, or identifying paths. Duplicate Dartitect or `sentry_dio`
instrumentation is rejected.

## Extending

Add application-specific interceptors at composition, returning domain-owned
contracts from repositories. Do not hide a global Dio instance behind Dartitect.

## Testing

Run `dart test`; use a mock Dio adapter and disable network. Cover concurrency,
cancellation, mapping, propagation, duplicate instrumentation, and disposal.

## Links

See [adapters](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/adapters.md),
[custom integrations](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/custom-integrations.md), and the [issue tracker](https://github.com/ftr-tuta/dartitect/issues).
