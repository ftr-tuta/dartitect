---
name: dartitect-observability
description: Configure Dartitect provider-neutral logging, reporting, W3C tracing, redaction, Flutter bindings, and payload-free reactive events. Use for telemetry contracts and policy; use the adapters skill for provider-specific wiring.
---

# Configure Dartitect observability

## When to use

Use this skill for `ObservabilityRuntime`, redaction/sampling/dispatch policy,
error reporting, W3C propagation, Flutter error capture, or reactive diagnostic
events and the versioned payload-free topology/lifecycle protocol.

## When not to use

Use `$dartitect-adapters` for Dio, Drift, ObjectBox, Sentry, or custom provider wiring.
Do not add remote telemetry merely because observability contracts exist.

## Invariants

Create the runtime explicitly; local developer logging is the safe default and
remote destinations are opt-in. Sanitize before every destination. Never record
credentials, authorization, cookies, bodies, headers, query strings, DSNs,
identity, identifying paths, domain payloads, or dynamic error text in reactive
events. Errors/fatal are never sampled away. Destination failure stays isolated.

## Workflow

Define the data policy first, then choose owned/borrowed sinks, reporter, tracer,
propagator, Flutter binding, reactive observers, and diagnostic detail. End every
span exactly once and define reverse flush/disposal. Use only emitter-owned
opaque IDs; keep buffers bounded and clear them on dispose.

Read [references/telemetry-contract.md](references/telemetry-contract.md),
[references/flutter-and-providers.md](references/flutter-and-providers.md), or
[references/reactive-events.md](references/reactive-events.md) for the boundary
being configured.

## Validate

Test redaction at every destination, unsampled error/fatal delivery, sink
isolation, queue bounds, exact-once span end, trace-context validation,
handler chaining/restoration/recursion, borrowed provider lifetime, and absence
of payload or identity in reactive events.

## Dartitect inclusion gate

Before adding a capability, answer:

> É business-neutral, difícil de implementar corretamente e gera infraestrutura repetitiva no consumidor?

All three answers must be “yes”. Otherwise the capability belongs in
`softgran_*`, `agrox_*`, or the application, not in a Dartitect package.
