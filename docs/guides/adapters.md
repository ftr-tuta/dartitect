# Adapters

## Composition

Create adapters in the app/session/isolate composition root. Infrastructure
implementations satisfy domain/application-owned contracts. No global client,
Store, Hub, or provider configuration belongs in Dartitect.

## Dio

Use `DioOwner.create` when the composition root owns and closes the real client;
use `.value` for a borrowed client. Header callbacks run for every request.
Expose cancellation, transport, HTTP, and configuration failures as distinct
types, and map only `DioException`; programming errors continue to throw. A
`CancelToken` is cooperative and does not prove transport preemption.

`DioObservabilityInterceptor` uses
`DioObservabilityCapturePolicy.metadataOnly()` by default. That path records
fixed method/protocol/status/error-type facts and zero payload. Transport
capture policy is separate from destination privacy policy.

`DioObservabilityCapturePolicy.diagnostic` is an explicit investigation mode.
Every captured field must carry reviewed classifications, and only JSON-safe
maps/lists/scalars are inspected. Streams, multipart values, bytes, and files
are never consumed. Remove Dio `LogInterceptor`: it can capture outside the
sanitizer. Propagate only through the configured W3C propagator and reject
duplicate Dartitect/`sentry_dio` instrumentation.

## ObjectBox

The consumer supplies its generated `openStore` callback and owns entities,
model JSON, generated Dart, migrations, transactions, and repositories.
Register subscriptions, timers, watchers, and queries with
`ObjectBoxObservationOwner`; drain that registry before closing Store.
Temporary cleanup removes only a directory created and validated by the same
invocation. Use a generated native fixture for tests. Never edit generated
files, assume web support, or transfer a Store object across isolates.

## Sentry

Borrow an injected, consumer-initialized Hub. Legacy `SentryLogSink`,
`SentryErrorReporter`, and `SentryTracer` remain defensive when connected to the
compatible runtime. Behind `ObservabilityRuntime.withPrivacy`, register only
`SentryLogSink.sanitizedInput`, `SentryErrorReporter.sanitizedInput`, and
`SentryTracer.sanitizedInput`; prepared events are not redacted twice.
Map approved bounded context to Sentry `extra`/context, keep tags allowlisted,
and never create an automatic `SentryUser`. Never set DSN, environment,
identity, or sampling, and never close the Hub. Test with a fake Hub and zero
network.

## Sync observability

Import `package:dartitect_observability/dartitect_observability_sync.dart` only
when a sync composition needs the payload-free adapter. The dependency is from
observability to sync; `dartitect_sync` remains independent and never imports or
emits telemetry automatically. Consumer dataset keys require an explicit value
classifier before they can be included.

## Reusable adapters

A proposal needs an isolated package, real boundary tests, public docs,
dependency rationale, compatible license, and updates to Dartitect skills.
