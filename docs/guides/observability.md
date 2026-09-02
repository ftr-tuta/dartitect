# Observability

## Compatibility and safe default

The `1.0.0` `ObservabilityRuntime`, `Redactor`, Dio telemetry, and direct Sentry
adapters remain available without deprecation. Existing applications do not
change behavior. New graphs should opt into destination-aware preparation with
the `balanced` profile:

```dart
final runtime = ObservabilityRuntime.withPrivacy(
  privacyPolicy: ObservabilityPrivacyPolicy.fromProfile(
    profile: ObservabilityPrivacyProfile.balanced,
  ),
  destinations: <ObservabilityDestinationRegistration>[
    ObservabilityDestinationRegistration.local(
      name: 'developer',
      logSinks: const <PreparedLogSinkRegistration>[
        PreparedLogSinkRegistration.owned(PreparedDeveloperLogSink()),
      ],
    ),
  ],
);

runtime.logger.info('Application started.');
await runtime.flush(const Duration(seconds: 1));
await runtime.disposeAsync();
```

Only private-constructor prepared events enter destination queues. A producer
cannot bypass the sanitizer by naming a constructor `sanitizedInput`, and a
queue never retains a closure over a raw event.

## Profiles and resolution

Profiles are reviewed starting points, not consent decisions:

| Profile | Local destinations | Remote destinations |
| --- | --- | --- |
| `strict` | Allow bounded safe facts; mask operational values; deny sensitive data | Allow bounded safe facts; mask operational values; deny sensitive data |
| `balanced` | Allow safe facts; mask identity, error messages, and operational identifiers | Allow safe facts; mask operational identifiers; deny identity and error messages |
| `diagnostic` | Allow explicitly classified bounded HTTP/error diagnostics except credentials, authorization, cookies, binary, multipart, and file content | Keep high-risk classes denied and mask paths, queries, and stacks unless a narrower reviewed rule applies |

Rules are resolved independently for every leaf classification. Each leaf may
find a rule on itself or a dotted ancestor; the results for multiple classes
then combine as `deny > mask > allow`. This order cannot be overridden.

Overrides can be global, apply to all local or remote destinations, or apply to
one validated named destination. Allowing a high-risk class at a remote
destination requires `ObservabilityRiskAcceptance.explicit`. Its reason is
configuration evidence and is never emitted as telemetry. Use `explain` or the
payload-free diagnostics view to inspect the winning action and rule source.

## Classification, masking, and bounded sanitization

Wrap consumer values in `ObservabilityClassifiedValue` with one or more
`ObservabilityDataClass` values. Application-defined dotted classes participate
in the same hierarchy. Built-in classifiers may supplement classifications;
they cannot erase an explicit class.

Masking can replace a complete value, preserve reviewed Unicode-safe edges, or
preserve a Unicode-safe center. The sanitizer handles only built-in safe types,
explicit classified values, or values accepted by an explicit projector. It
never calls `toString()` on unknown objects or arbitrary map keys.

Deterministic limits cover nesting depth, collection size, total visited nodes,
text code points, stack frames, and classification work. Identity-cycle
detection, collision-safe masked keys, inline secret detectors, URI/HTTP/error/
stack projections, and immutable results prevent work amplification and raw
retention. Structural budgets are required test gates; elapsed-time benchmarks
are informative and calibrated for the host.

## Destinations, diagnostics, and flush

Each `ObservabilityDestinationRegistration` has a validated unique name,
local/remote kind, capabilities, sampling state, bounded queue, ownership, and
failure counters. Conflicting ownership or duplicate registrations fail during
composition. A slow or failing remote sink, reporter, or tracer cannot block or
fail a local destination.

`diagnostics` returns a fresh immutable snapshot containing only counts and
queue facts. `flush(Duration)` retains its compatible aggregate behavior;
`flushDetailed(Duration)` returns completion, timeout, and isolated failure
counts by destination.

## Tracing

Accept only valid W3C `traceparent`. `tracestate` has separate validation and
privacy policy and is never transformed into an attribute, tag, or baggage
item. Baggage remains off by default. End every span exactly once in `finally`,
and transfer only validated trace data between isolates.

## Dio and Sentry

Dio capture policy is independent of destination policy. Metadata-only capture
is the default and records no payload. Diagnostic capture requires explicit
classifications and accepts only JSON-safe structures; it never consumes
streams, multipart values, bytes, or files. Remove `LogInterceptor` and reject
duplicate Dartitect or `sentry_dio` capture.

Prepared Sentry adapters are constructed with `.sanitizedInput` and can be
registered only behind the destination-aware runtime. They map approved context
to bounded Sentry context/extra data, limit tags, borrow the consumer's Hub, and
never create a `SentryUser`. Legacy adapters remain defensive and redact again
when used directly; prepared adapters do not perform a second redaction pass.

## Payload-free runtime diagnostics

Diagnostics protocol v2 remains exactly three read-only service extensions for
capabilities, snapshots, and deltas. It is unchanged by this feature. Privacy
inspection uses the separate `ext.dartitect.observabilityPrivacy` registration,
which exposes schema, profile, masking mode, effective class actions, queue
counts, failure counts, and sanitization counts. It exposes no values, samples,
messages, stacks, keys, or risk-acceptance reasons.

Reactive, sync, Drift, ObjectBox, jobs, transfer, isolate, Workmanager, and
Flutter integrations emit only reviewed payload-free facts. The optional sync
adapter is imported from `dartitect_observability_sync.dart`; `dartitect_sync`
does not depend on observability.

## Errors and ownership

Expected `Err<F>` values remain application state. Unexpected crashes may be
reported once with reviewed classifications and then rethrown. Stop producers
and bindings, flush/dispose the runtime, and only then close consumer-owned
provider SDKs. Rebuild the graph in every isolate.

The privacy API is additive and does not introduce config v4. Generated
developer wiring selects `balanced`; remote providers still require explicit
consumer composition and policy review.
