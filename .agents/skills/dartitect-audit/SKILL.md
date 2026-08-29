---
name: dartitect-audit
description: Audit a Dartitect-created project for Native Strict conformance without changing it. Use for read-only evidence after development or a Dartitect SDK upgrade.
---

# Audit Dartitect conformance

## When to use

Use this skill when a project created with Dartitect must revalidate its
architecture, globals, providers, lifecycle, or SDK upgrade evidence.

## When not to use

Use `$dartitect-design` for implementation choices. Do not use this skill to
perform migration or authorize provider leakage, service location, duplicate
ownership, or concrete runtime boundaries.

## Invariants

Inspection is read-only. Report evidence without modifying code, dependencies,
configuration, baselines, or generated files. Treat `dartitect verify` and
`scan --no-baseline` as canonical read-only evidence. Installed Riverpod, BLoC,
Provider, GetIt, MobX, Signals, or equivalent architecture runtimes are Native
Strict errors. Provider leakage, service location, duplicate ownership, and
dual-write are also errors.

## Workflow

1. Record tests, analyzer, `dartitect doctor`, and `dartitect scan --no-baseline`.
2. Inventory composition roots, owners, disposal order, repositories,
   background entrypoints, provider SDKs, and telemetry paths.
3. Classify each boundary as conforming, non-conforming, or not evidenced.
4. Record prohibited runtime packages separately from advisory alternatives and
   approved consumer-owned infrastructure.
5. Return a conformance report, upgrade observations, and the exact commands
   used; do not mutate or claim adoption or automatic conversion.

Read [references/inventory.md](references/inventory.md) for evidence collection
and [references/conformance-audit.md](references/conformance-audit.md) for the
CLI/MCP boundary.

## Validate

Confirm the report is reproducible, contains no write or migration action, uses
the unbaselined scan, and distinguishes unsupported architecture runtimes from
consumer-owned infrastructure packages.

## Dartitect inclusion gate

Before adding a capability, answer:

> É business-neutral, difícil de implementar corretamente e gera infraestrutura repetitiva no consumidor?

All three answers must be “yes”. Otherwise reusable infrastructure belongs in
a typed project-local extension and business behavior stays in the application.
