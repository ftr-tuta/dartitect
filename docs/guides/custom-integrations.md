# Custom integrations

[Português (Brasil)](custom-integrations.pt-BR.md)

## Goal

Integrate a database, HTTP client, observability backend, cache, queue, or other
tool without requiring official Dartitect support. Keep the provider isolated
behind small application-owned contracts.

## Ownership adapter

Use `ResourceOwner` for values whose disposal callback lives at composition, or
implement `AsyncDisposable` when the adapter itself has asynchronous shutdown:

```dart
final resources = ResourceOwner(label: 'session');
final client = resources.own(
  VendorClient(configuration),
  (value) => value.close(),
  label: 'Vendor client',
);
```

Mark borrowed values explicitly in the composition code and never register
them for disposal. Dispose consumers/watchers before the provider.

## Architecture events

Accept an `ArchitectureObserver` with `NoOpArchitectureObserver` as the default.
Emit acquisition, release, failure, and use-after-dispose facts. Observer
failure must never change provider or application behavior.

## Logs and errors

Implement `LogSink` and/or `ErrorReporter`. Convert only already-sanitized
`LogEvent`/`ErrorEvent` fields. Redact again at the destination if the provider
adds context. Never map bodies, headers, queries, credentials, DSNs, identity,
or identifying paths.

```dart
final class VendorLogSink extends LogSink {
  VendorLogSink(this.client);
  final VendorClient client; // borrowed

  @override
  Future<void> emit(LogEvent event) => client.write(
    level: event.level.name,
    message: event.message,
  );
}
```

## Tracing

Implement `Tracer` and return a `Span` whose `end` is idempotent. Map a minimal
attribute allowlist, accept only valid W3C context, and finish once in `finally`.
Keep provider propagation opt-in; do not inject headers behind the consumer's
back.

## Consumer-owned data

Entities, database/serialization schemas, credentials, DSNs, endpoints,
encryption keys, generated code, migrations, and all vendor configuration stay
consumer-owned. Dartitect adapters receive configured objects; they do not load
secrets or initialize a global provider.

## Testing

Use a real boundary fixture where lifecycle/locking/code generation matters and
a deterministic fake where network would otherwise be required. Cover acquire
failure, partial configuration, concurrency, cancellation, exact-once shutdown,
borrowed lifetime, redaction, destination failure, and zero residual resources.

## Proposing an official adapter

A reusable PR must include an isolated optional package, tests against the real
SDK boundary, public English/pt-BR docs, an executable or configuration example,
dependency/version rationale, license and advisory review, public API snapshot,
and updates to the adapter/testing/conformance skills. Official support remains a
maintainer decision; consumer-owned custom integration is always valid.
