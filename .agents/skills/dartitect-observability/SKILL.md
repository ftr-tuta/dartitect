---
name: dartitect-observability
description: Configure Dartitect destination-aware privacy, provider-neutral logging/reporting/tracing, bounded sanitization, prepared destinations, and payload-free diagnostics. Use for telemetry contracts and policy; use the adapters skill for provider-specific wiring.
---

# Configure Dartitect observability

## When to use

Use this skill for `ObservabilityRuntime.withPrivacy`, profiles,
classifications, masking, bounded sanitization, prepared destination queues,
error reporting, W3C propagation, Flutter error capture, or payload-free
runtime diagnostics. Use the compatible runtime only when preserving a 1.0
composition.

## When not to use

Use `$dartitect-adapters` for Dio, Drift, ObjectBox, Sentry, or custom provider wiring.
Do not add remote telemetry merely because observability contracts exist.

## Invariants

Create the runtime explicitly; generated graphs start with the `balanced`
profile and a prepared local developer destination. Remote destinations are
opt-in. Resolve each leaf classification through its hierarchy, then combine
multiple decisions as `deny > mask > allow`. High-risk remote allows require
explicit risk acceptance. Only immutable prepared events enter independent
destination queues; never retain raw input or call `toString()` on unknown
objects/keys. Errors/fatal are never sampled away. Destination failure stays
isolated.

## Workflow

Define the data classes and local/remote/named policy first, then choose
owned/borrowed prepared sinks, reporter, tracer, propagator, Flutter binding,
reactive observers, and diagnostic detail. Bound depth, collections, total
nodes, text, frames, and classification work. End every span exactly once and
define reverse flush/disposal. Use only emitter-owned opaque IDs; keep buffers
bounded and clear them on dispose.

Read [references/telemetry-contract.md](references/telemetry-contract.md),
[references/flutter-and-providers.md](references/flutter-and-providers.md), or
[references/reactive-events.md](references/reactive-events.md) for the boundary
being configured.

## Validate

Test the profile/local/remote/named matrix, precedence, raw-secret sentinels,
cycles, key collisions, Unicode masking, structural budgets, unsampled
error/fatal delivery, destination isolation, detailed flush, exact-once span
end, `traceparent`/`tracestate` validation, borrowed provider lifetime, and
payload-free diagnostics.

## Dartitect inclusion gate

Before adding a capability, answer:

> Is it business-neutral, difficult to implement correctly, and a source of
> repetitive infrastructure in consumer applications?

All three answers must be “yes”. Otherwise reusable infrastructure belongs in
a typed project-local extension and business behavior stays in the application.
