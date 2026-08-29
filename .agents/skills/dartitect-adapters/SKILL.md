---
name: dartitect-adapters
description: Integrate Dartitect with Dio, Drift, ObjectBox, Sentry, or a custom provider using isolated provider references and explicit ownership. Use for infrastructure wiring; do not use to select application architecture or define domain policy.
---

# Integrate Dartitect adapters

## When to use

Use this skill after the application has selected a transport, storage, or
telemetry provider and needs to wire its Dartitect adapter at composition.

## When not to use

Use `$dartitect-design` to decide whether a provider is needed,
`$dartitect-observability` for neutral telemetry policy, and
`$dartitect-offline-first` for repository/outbox semantics.

## Invariants

Create adapters in an app/session/isolate infrastructure composition root.
Provider SDKs, generated models, credentials, and configuration remain
consumer-owned. No global client, Store, Hub, or adapter crosses into domain,
application, ViewModel, or presentation. Record owned/borrowed lifetime and
dispose borrowers before providers. Storage schemas have one consumer-owned
writer; never introduce dual-write, automatic cross-engine migration, a schema
bridge, or a cross-engine transaction.

## Workflow

Select exactly one provider reference below, define the application-owned
contract it implements, wire ownership and sanitized telemetry, then test the
real SDK boundary plus deterministic failure cases.

- Dio: [references/dio.md](references/dio.md)
- Drift: [references/drift.md](references/drift.md)
- ObjectBox: [references/objectbox.md](references/objectbox.md)
- Drift + ObjectBox coexistence: [references/coexistence.md](references/coexistence.md)
- Sentry: [references/sentry.md](references/sentry.md)
- Another provider: [references/custom-provider.md](references/custom-provider.md)

## Validate

Verify typed failure mapping, cancellation/concurrency where applicable,
minimal telemetry, provider ownership, reverse disposal, no duplicate
instrumentation, real boundary compatibility, and zero residual resources.

## Dartitect inclusion gate

Before adding a capability, answer:

> É business-neutral, difícil de implementar corretamente e gera infraestrutura repetitiva no consumidor?

All three answers must be “yes”. Otherwise the capability belongs in
`softgran_*`, `agrox_*`, or the application, not in a Dartitect package.
