---
name: dartitect-flutter-quality
description: Implement or audit executable Flutter quality in a Native Strict Dartitect application. Use for responsive constraints, previews, MVVM/repositories, DevTools runtime evidence, multi-platform behavior, tests, or structural performance; coordinate Flutter's official skills instead of copying them.
---

# Prove Flutter quality

## When to use

Use this skill when Flutter quality must be demonstrated by source, previews,
runtime inspection, tests, platforms, or agent-evaluation evidence.

## When not to use

Use `$dartitect-ui` for ordinary presentation composition and the focused
runtime, offline-first, testing, or performance skill for a non-Flutter
boundary. Do not install plugins or claim unavailable MCP tools.

## Invariants

Apply Native Strict. Keep widgets value/callback-only, ViewModels responsible
for state/commands/effects, repositories provider-neutral, and exactly one
store selected at composition. Previews are dev-only, synthetic, immutable,
and free of I/O, adapters, plugins, globals, and app lifecycle.

## Workflow

Route the task by name to the applicable official skills:
`flutter-apply-architecture-best-practices`,
`flutter-build-responsive-layout`, `flutter-fix-layout-issues`,
`flutter-add-widget-preview`, `flutter-add-widget-test`, and
`flutter-add-integration-test`. Use only skills actually discovered from
`dart-flutter@dart-flutter`; do not duplicate their instructions.

Read [references/architecture-and-previews.md](references/architecture-and-previews.md)
for MVVM, repositories, responsive composition, and preview safety. Read
[references/runtime-devtools-and-mcp.md](references/runtime-devtools-and-mcp.md)
when live inspection is applicable. Read
[references/tests-and-evidence.md](references/tests-and-evidence.md) for the
verification matrix. Read [references/performance.md](references/performance.md)
for structural budgets and informative measurements.

## Validate

Require explicit analyze, strict audit, preview compilation, runtime inspection,
tests, and platform evidence. Mark unavailable MCP or a missing applicable
dimension as not evidenced. Never store transcripts, screenshots, semantics,
or visible content in evaluation receipts.

## Dartitect inclusion gate

Before adding a capability, answer:

> Is it business-neutral, difficult to implement correctly, and a source of
> repetitive infrastructure in consumer applications?

All three answers must be “yes”. Otherwise reusable infrastructure belongs in
a typed project-local extension and business behavior stays in the application.
