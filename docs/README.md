# Dartitect documentation

This is the canonical task-oriented entrypoint for Dartitect documentation.
Public guidance is maintained in English and describes the stable `1.0.0`
GitHub-only distribution unless a page is explicitly classified as migration
input or historical evidence.

## Adopt Dartitect in a greenfield project

- Start with [Getting started](guides/getting-started.md).
- Select the minimum package set with [Ecosystem selection](guides/ecosystem-selection.md).
- Check the non-negotiable architecture boundary in the [Native Strict matrix](guides/native-strict-matrix.md).
- Use the generated path described by the [greenfield vertical platform](guides/paved-road-platform.md).
- Consume the stable cohort from the [Git release](guides/git-release-consumption.md).

## Compose and own resources

- Define stable generated inputs with [config v3](guides/config-v3.md).
- Design scope, ownership, teardown, and isolate boundaries with
  [Composition, lifecycle, and isolates](guides/composition-lifecycle-isolates.md).
- Model typed failures, command scheduling, and transient UI delivery with
  [Commands, results, and effects](guides/commands-results-effects.md).
- Keep non-neutral reusable infrastructure in
  [typed project-local extensions](guides/project-local-extensions.md).

## Build runtime and presentation

- Use the [implementation recipes](guides/implementation-recipes.md) for
  complete public-entrypoint examples.
- Opt into the [reactive runtime](guides/reactive-runtime.md) only when basic
  commands and ViewModels are insufficient.
- Keep authenticated work generation-scoped with
  [credential generations](guides/credential-generations.md).
- Apply the [business-neutral UI quality](guides/ui-quality.md) boundary to
  consumer-owned Material or Cupertino presentation.

## Add persistence, transport, and optional capabilities

- Wire consumer-owned providers with [Adapters](guides/adapters.md).
- Choose storage and synchronization boundaries in the
  [ecosystem selection matrix](guides/ecosystem-selection.md) and
  [implementation recipes](guides/implementation-recipes.md).
- Review the frozen native and pure-Dart limits in
  [Optional capability contracts](guides/optional-capabilities.md).
- Define vendor-neutral diagnostics and data handling with
  [Observability](guides/observability.md) and
  [Custom integrations](guides/custom-integrations.md).

## Operate tooling

- Treat config v3 as the only normal configuration contract; use
  [config v2](guides/config-v2.md) only as transactional migration input.
- Use [Fleet tooling](guides/fleet-tooling.md),
  [model generation](guides/model-generation.md), and
  [bounded OpenAPI contracts](guides/openapi-contracts.md) for their focused
  generated surfaces.
- Measure authored and generated infrastructure separately with
  [consumer-tax ratchets](guides/consumer-tax.md).
- Configure the local, bounded [MCP server](guides/mcp.md) only for interactive
  development workflows.

## Test and verify

- Follow each package README's testing section and the
  [implementation recipe verification matrix](guides/implementation-recipes.md#validation).
- Use real generated/provider fixtures when lifecycle or code generation is
  part of the contract; use deterministic no-network fakes for policy.
- Run the repository gates documented in the
  [contribution workflow](guides/repository-contribution.md).

## Contribute

- Read [CONTRIBUTING.md](../CONTRIBUTING.md), the
  [repository contribution workflow](guides/repository-contribution.md), and
  the applicable `AGENTS.md` before changing tracked content.
- Update the canonical skill templates in
  `packages/dartitect_cli/lib/src/codex/skill_catalog.dart`; never hand-edit a
  managed snapshot under `.agents/skills/dartitect-*`.
- Add user-facing changes to the uniform `Unreleased` section in all 25 package
  changelogs. A future numbered release requires separate authorization.

## Migration and historical records

- [MIGRATIONS.adoc](../MIGRATIONS.adoc) and
  [config v2](guides/config-v2.md) are migration-entry documents. They do not
  describe normal stable configuration.
- [Architecture decisions](adr/) preserve decisions in their original context.
  Legacy numbering, including both ADR 0038 records, is intentionally not
  rewritten or renumbered.
- [Release evidence](release/) records the completed `1.0.0` release and its
  pre-release handoffs. RC handoffs and the executed publication runbook are
  historical, not reusable release instructions.
- [Research](research/) and [work records](work/) preserve the evidence,
  assumptions, and status that applied when each record was written. They may
  contain superseded RC terminology and must not be read as current guidance.

`tool/documentation_contract.json` is the machine-readable classification for
current, migration-entry, historical, and generated documentation. The public
documentation and skill checkers reject unclassified files, duplicate guides,
broken links/includes, incomplete sections, malformed blocks, stale
release-candidate language in current guidance, and managed-skill drift.
