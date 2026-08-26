---
name: dartitect-modeling
description: Define, generate, validate, or review immutable Dartitect value models with DartitectValue, ValueEquality, typed copyWith, and model sync/check. Use for Dartitect-owned value generation; exclude DTO/JSON, unions, DI, ViewModels, state, and HTTP clients.
---

# Model values with Dartitect

## When to use

Use this skill for `@DartitectValue()`, generated value semantics, typed
`copyWith`, model ownership manifests, or `model sync/check`.

## When not to use

Use provider-specific tooling for DTO/JSON, schema, or native generators. Use
the runtime, reactive, adapters, or tooling skill for ViewModels, state, HTTP,
DI, and unrelated CLI behavior.

## Invariants

Keep the annotation passive in `dartitect`; generation belongs to the CLI. One
source library contains exactly one annotated final, non-generic class. Declare
the matching `part`, extend `ValueEquality`, mix in the calculated generated
mixin, expose typed public final fields, and use one unnamed generative
constructor whose named parameters correspond exactly to those fields.

Do not declare fields through mutable collection interfaces such as `List`,
`Set`, `Map`, or `Iterable`; wrap immutable values in a consumer-owned type.
Generation does not own JSON, DTOs, unions, DI, ViewModels, state, routes, or
clients and may coexist with provider-owned generators in distinct part files.

## Workflow

Use `dartitect model sync` for a read-only preview, or `--dry-run` for an
explicit preview. Only `dartitect model sync --apply` may recover and converge
outputs. Run `dartitect model check` in CI. Commit every
`*.dartitect.g.dart` output and `.dartitect/model-outputs.json` so a clean
checkout compiles without installing the CLI.

Never hand-edit or force-adopt a generated model. A digest conflict means the
consumer bytes must be reviewed and ownership restored explicitly. A pending
journal is inspected by preview/check and recovered only by `sync --apply`.

## Validate

The generated mixin supplies abstract getters, `equalityFields`, and typed
`copyWith` only. Nullable fields preserve on omission, replace on a non-null
value, and clear with `clear<Field>: true`; passing a value and clear together
must fail. Non-nullable fields have no clear flag. Do not generate equality,
hashing, or `toString` because `ValueEquality` centralizes those semantics.

Test bootstrap with the exact missing part/mixin only, clean post-sync analysis,
preserve/replace/clear behavior, full equality participation, create/update/
no-op/orphan convergence, consumer edits, manifest corruption/path escapes,
CRLF canonicalization, pending recovery, and stable JSON/exit codes.
