# Adapters

## Composition

Create adapters in the app/session/isolate composition root. Infrastructure
implementations satisfy domain/application-owned contracts. No global client,
Store, Hub, or provider configuration belongs in Dartitect.

## Dio

Expose cancellation, transport, HTTP, and configuration failures as distinct
types. Instrument method/protocol/status only. Propagate through the configured
W3C propagator and reject duplicate Dartitect/`sentry_dio` instrumentation.

## ObjectBox

The consumer owns entities and generated model. Close watchers and queries
before Store. Use a generated native fixture for tests. Never edit generated
files, assume web support, or transfer a Store object across isolates.

## Sentry

Borrow an injected, consumer-initialized Hub. Never initialize, configure, or
close it. Test with a fake Hub and zero network.

## Reusable adapters

A proposal needs an isolated package, real boundary tests, public docs,
dependency rationale, compatible license, and updates to Dartitect skills.
