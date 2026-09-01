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

Instrument method/protocol/status only. Never record headers, bodies, query
strings, credentials, or user information. Propagate through the configured W3C
propagator and reject duplicate Dartitect/`sentry_dio` instrumentation.

## ObjectBox

The consumer supplies its generated `openStore` callback and owns entities,
model JSON, generated Dart, migrations, transactions, and repositories.
Register subscriptions, timers, watchers, and queries with
`ObjectBoxObservationOwner`; drain that registry before closing Store.
Temporary cleanup removes only a directory created and validated by the same
invocation. Use a generated native fixture for tests. Never edit generated
files, assume web support, or transfer a Store object across isolates.

## Sentry

Borrow an injected, consumer-initialized Hub in `SentryLogSink`,
`SentryErrorReporter`, and `SentryTracer`. Never set DSN, environment, identity,
or sampling, and never close the Hub. Test with a fake Hub and zero network.

## Reusable adapters

A proposal needs an isolated package, real boundary tests, public docs,
dependency rationale, compatible license, and updates to Dartitect skills.
