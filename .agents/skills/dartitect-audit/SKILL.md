---
name: dartitect-audit
description: Audit an existing Dart or Flutter codebase for Native Strict conformance without changing it. Use for read-only evidence; Dartitect 1.0 is greenfield-only and provides no migration or coexistence workflow.
---

# Audit Dartitect conformance

## When to use

Use this skill when existing architecture, globals, providers, violations, or
lifecycle assumptions must be assessed against Native Strict boundaries.

## When not to use

Use `$dartitect-design` for a new application or feature. Do not use this skill
to convert an existing runtime, plan staged migration, or authorize coexistence
with another DI or application-state runtime.

## Invariants

Inspection is read-only. Report evidence without modifying code, dependencies,
configuration, baselines, or generated files. Treat `scan --no-baseline` as the
canonical conformance gate. Existing projects may be audited, but Dartitect 1.0
does not support runtime migration, compatibility shims, or coexistence with a
competing DI/application-state architecture.

## Workflow

1. Record tests, analyzer, `dartitect doctor`, and `dartitect scan --no-baseline`.
2. Inventory composition roots, owners, disposal order, repositories,
   background entrypoints, provider SDKs, and telemetry paths.
3. Classify each boundary as conforming, non-conforming, or not evidenced.
4. Record prohibited runtime packages separately from advisory alternatives and
   approved consumer-owned infrastructure.
5. Return a conformance report and the exact commands used; do not emit a
   conversion plan.

Read [references/inventory.md](references/inventory.md) for evidence collection
and [references/conformance-audit.md](references/conformance-audit.md) for the
CLI/MCP boundary.

## Validate

Confirm the report is reproducible, contains no write or migration action, uses
the unbaselined scan, and distinguishes unsupported architecture runtimes from
consumer-owned infrastructure packages.
