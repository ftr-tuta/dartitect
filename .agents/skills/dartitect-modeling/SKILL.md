---
name: dartitect-modeling
description: Define, generate, validate, or review opt-in Dartitect values, JSON codecs, projections, lenses, and boundary mappers. Use for consumer-owned modeling and model sync/check/migration; exclude provider schema, DI, ViewModels, state, and HTTP clients.
---

# Model values with Dartitect

## When to use

Use this skill for the independent `@DartitectValue()`, `@DartitectJson()`,
`@DartitectProjection()`, and `@DartitectMapper()` capabilities, generated
value semantics, codecs, projections/lenses, pure mappers, ownership manifests,
or `model sync/check/migrate primary`.

## When not to use

Use provider-specific tooling for provider DTO/entity schema or native generators. Use
the runtime, reactive, adapters, or tooling skill for ViewModels, state, HTTP,
DI, and unrelated CLI behavior.

## Invariants

Keep annotations passive in `dartitect_modeling`; generation belongs to host
tooling. A source library may contain multiple annotated final classes and owns
one deterministic Dartitect part. Models use a primary constructor, extend
`ValueEquality`, expose immutable typed fields, and may be generic, const, use
defaults, records, and parts when the shared semantic compiler validates them.

Use `ImmutableValueList`, `ImmutableValueSet`, and `ImmutableValueMap` for
structural collection fields. JSON, projections, and mappers are never enabled
by the value marker. Unknown JSON keys reject by default, untrusted limits are
64 depth/10,000 items/100,000 nodes, and any trusted or custom limit choice is
explicit. Mappers automate only assignable lossless fields; renames and static
consumer hooks are explicit. Never infer narrowing, enum/string, dates, IDs,
relations, or flattening. Provider-owned generators use distinct outputs.

## Workflow

Use `dartitect model sync` for a read-only preview, or `--dry-run` for an
explicit preview. Only `dartitect model sync --apply` may recover and converge
outputs. Run `dartitect model check` in CI. Commit every
`*.dartitect.g.dart` output and namespaced manifest so a clean
checkout compiles without installing the CLI.

Use `dartitect model migrate primary` to preview traditional-to-primary
constructor edits. Only `--apply` may take the project lock, journal source
bytes, revalidate, and commit or roll back the complete semantic edit.

Never hand-edit or force-adopt a generated model. A digest conflict means the
consumer bytes must be reviewed and ownership restored explicitly. A pending
journal is inspected by preview/check and recovered only by `sync --apply`.

## Validate

The generated model surface supplies `equalityFields`, descriptors/lenses, and
typed `copyWith`. Nullable fields preserve on omission, replace on a non-null
value, and clear with `clear<Field>: true`; passing a value and clear together
must fail. Non-nullable fields have no clear flag. Do not generate equality,
hashing, or `toString` because `ValueEquality` centralizes those semantics.

Test primary constructors, generics, const/defaults, records, multiple models,
preserve/replace/clear behavior, defensive structural collections, JSON
round-trip/malformed/bounds, projection selection, lossless/lossy mapping and
hooks. Also cover create/update/no-op/orphan convergence, migration preview/
apply/recovery, consumer edits, manifest corruption/path escapes, CRLF,
concurrency, pending recovery, and stable JSON/SARIF/exit codes.
