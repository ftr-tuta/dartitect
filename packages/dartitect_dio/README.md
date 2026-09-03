# dartitect_dio

## Purpose

Optional ownership, typed failure mapping, cancellation binding, route-template
validation, JSON transport, W3C propagation, and minimal telemetry around the
real Dio API.

## When to use

Use it at an infrastructure composition root after the application has selected
Dio. It is useful when owned/borrowed client lifetime, typed transport failures,
core cancellation, or sanitized observability must be consistent.

## When not to use

Do not use it as the domain-facing HTTP API, before selecting Dio, or alongside
another interceptor that performs the same trace propagation or capture. Do not
import Dio or this package into domain, application, ViewModel, or presentation
code.

## Platforms and entrypoints

Import `package:dartitect_dio/dartitect_dio.dart`. It supports the platforms
supported by the selected Dio adapter, including Dart VM, Flutter, and web where
the consumer configuration supports them.

## Mental model and data flow

The composition root creates or borrows a Dio client. Infrastructure
repositories resolve a validated `RouteTemplate`, send through
`DioJsonClient`/Dio, bind a caller-owned cancellation signal, and map
`DioException` into an exhaustive `DioFailure`. Neutral telemetry and W3C
context are injected by explicit interceptors. Domain code receives only
application-owned ports and failure/value types.

## Minimal workflow

```dart
import 'package:dartitect_dio/dartitect_dio.dart';

void main() {
  final owner = DioOwner.create();
  try {
    if (!owner.ownsClient || owner.isDisposed) {
      throw StateError('Dio ownership invariant failed.');
    }
  } finally {
    owner.dispose();
  }
}
```

Use `DioOwner.value(existingDio)` when another composition owns and closes the
client.

## Public API tour

- `DioOwner.create` owns/closes a client; `DioOwner.value` borrows one.
- `DioJsonClient` and `DefaultDioJsonClient` provide typed JSON request/response
  mapping over the borrowed Dio client.
- `DioEndpoint`, `DioResponse`, `RouteTemplate`, and
  `RouteTemplateResolver` define validated endpoint and route expansion.
- `DioFailure` variants distinguish cancellation, HTTP, transport,
  configuration, decoding, and route failures.
- `captureDioException` maps Dio failures to `Result` without swallowing
  unrelated exceptions.
- `bindCancelToken` and `ownCancelToken` bridge core cancellation and explicit
  token ownership.
- `DartitectHeadersInterceptor` propagates configured W3C context.
  `DioTelemetryInterceptor`, `DioInstrumentation`, events, and observer types
  emit fixed minimal facts and reject duplicate instrumentation.
- `DioObservabilityInterceptor` separates transport capture from destination
  privacy. `DioObservabilityCapturePolicy.metadataOnly()` is the zero-payload
  default; `.diagnostic()` requires explicit classifications and accepts only
  JSON-safe structures.
- `DioCredentialsInterceptor` attaches a generation-fenced credential lease,
  binds waiting to `CancelToken`, and invalidates only the generation rejected
  by the provider. Replay requires an explicit `DioCredentialReplayPolicy` and
  borrowed retry client, is limited to one, and excludes stream/multipart data.

## Ownership and lifecycle

Create the client at an app/session/isolate composition root. `.create` owns it;
`.value` borrows it. Dispose request scopes, cancellation registrations/tokens,
repositories, and interceptors before an owned client. A shared `CancelToken` is
borrowed by the binding; the cancellation source remains caller-owned.

A receiving isolate constructs its own Dio instance and interceptors. Never
transfer a live client or interceptor graph.

## Failure, cancellation, and concurrency

Typed failures retain their category and safe metadata. Expected HTTP/transport
outcomes can be mapped into application failures; unrelated unexpected
exceptions keep their stack. Cancellation has its own failure type and must not
be presented as a transport or domain rejection.

Core cancellation triggers the bound Dio token. Cancelling one request must not
dispose a shared client or cancel another credential waiter. Dio governs
concurrent requests; Dartitect adds no unbounded queue or hidden retry loop.
Duplicate Dartitect instrumentation or overlap
with `sentry_dio` is rejected to avoid double capture.

## Prohibited uses and limitations

- No global Dio instance or service-location wrapper.
- No provider types in inward-facing APIs.
- No default authenticated replay, caching, schema validation, or offline
  transaction. One replay exists only behind consumer idempotency policy.
- No duplicate tracing/capture interceptors.
- No Dio `LogInterceptor` beside classified capture.
- No telemetry containing bodies, headers, query values, credentials, tokens,
  identity, or identifying paths.

Diagnostic capture never consumes streams, multipart values, byte payloads, or
files. Metadata-only remains the production default.

Route templates validate shape but do not define an application's endpoint or
authorization policy.

## Testing

Run `dart test` with a deterministic Dio adapter and network disabled. Cover
owned/borrowed disposal, route validation/encoding, JSON success and decoding
failure, every `DioFailure` category, cancellation, concurrent requests, W3C
propagation, duplicate instrumentation, redaction, and observer isolation.

## Related packages and guides

Combine with `dartitect_observability` for neutral policy, `dartitect_sync` only
behind a consumer repository/outbox boundary, and `dartitect_testing` for
deterministic tests. Read [adapters](../../docs/guides/adapters.md) and
[custom integrations](../../docs/guides/custom-integrations.md), and
[credential generations](../../docs/guides/credential-generations.md).

## Availability

Dartitect `1.1.0` is distributed only by the annotated `v1.1.0` tag and
its immutable GitHub Release. Declare this package directly with the canonical
Git descriptor; its transitive Dartitect dependencies resolve from the same tag
without overrides. See the
[Git release consumption guide](../../docs/guides/git-release-consumption.md).

`DioTransferTransport` also connects `dartitect_transfer` to a borrowed Dio
client. Its callbacks leave URL, headers, credentials, Range/ETag,
idempotency, response validation, and durable-commit semantics with the
consumer; the adapter emits no request logs.
