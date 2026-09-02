---
name: dartitect-testing
description: Test Dartitect consumers, failure and lifecycle matrices, real provider fixtures, and residual-resource cleanup with deterministic fakes. Use for verification or leak diagnosis; do not use as a substitute for implementation design.
---

# Test Dartitect boundaries

## When to use

Use this skill when selecting fakes, fixtures, public entrypoints, lifecycle/
failure scenarios, provider boundary tests, or cleanup assertions.

## When not to use

Use the focused implementation skill to define the behavior first. Do not mock
away the SDK boundary whose compatibility the test is meant to prove.

## Invariants

Test through public entrypoints. Prefer deterministic fakes from
`dartitect_testing`; inject clocks, IDs, destinations, executors, process
runners, and filesystem roots. Use real generated/provider fixtures where code
generation or SDK lifecycle is the contract. Disable network. Every test owns
and disposes what it creates and proves no residual resources.

## Workflow

Build a matrix across success, expected failure, unexpected crash,
cancellation/concurrency, lifecycle temperature, disposal, and provider failure.
Choose deterministic fakes for policy and real fixtures for integration.
For a public feature profile, run the matching `FeatureContractMatrix.local`,
`.online`, `.cache`, `.replica`, or `.offlineFull`; each required row gets a fresh typed
runtime driver. The matrix owns faults, event journal, observed store,
acknowledgements, graph registrations, and `ResourceCensus`; fixtures never
return facts or a residual map. Derive success, expected failure, crash,
cancellation, concurrency, restart, and teardown evidence from those observed
instruments.
Prefer the generated `<Feature>FeatureHarness` in `test/support`; consumers add
only domain fixtures, selected policies, and domain assertions.

Read [references/runtime-and-reactive.md](references/runtime-and-reactive.md),
[references/sync.md](references/sync.md),
[references/provider-fixtures.md](references/provider-fixtures.md),
[references/platform-and-background.md](references/platform-and-background.md), or
[references/tooling.md](references/tooling.md) for the boundary under test.

## Validate

Assert observable state and ownership rather than internal wording. Include
original-stack rethrow, exact-once reporting/span end, stale-completion
rejection, handler restoration, sink isolation, timers/subscriptions/isolates
drained, and zero network or leaked filesystem artifacts.

## Dartitect inclusion gate

Before adding a capability, answer:

> É business-neutral, difícil de implementar corretamente e gera infraestrutura repetitiva no consumidor?

All three answers must be “yes”. Otherwise reusable infrastructure belongs in
a typed project-local extension and business behavior stays in the application.
