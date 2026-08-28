# Dartitect model generation

[Português (Brasil)](model-generation.pt-BR.md)

## 1.0 scope and source contract

Model generation is limited to opt-in immutable value, JSON, projection, and
boundary-mapping boilerplate. The generator scans
`lib/**` and each immediate `packages/*/lib/**` tree without following symlinks.
An annotated source library may contain models in its defining unit and parts;
all models share one deterministic Dartitect part.

| Contract | Supported 1.0 form | Rejected form |
|---|---|---|
| Annotation | Independent `@DartitectValue()`, `@DartitectJson()`, `@DartitectProjection(...)`, and `@DartitectMapper(...)` elements resolved from `package:dartitect_modeling`, including prefixes and reexports | Homonymous, unresolved, or implicitly enabled capabilities |
| Class | Concrete `final`, extends `ValueEquality`, mixes in `_$TypeDartitect` | Abstract, non-final, or complex inheritance |
| Part | Exactly one `part '<source>.dartitect.g.dart';` | Missing, duplicate, or mismatched part |
| Fields | At least one public, typed, named `final` primary-constructor field | Private, inferred, positional, late, or mutable fields |
| Collections | Consumer-owned immutable class wrapper types | Mutable collection interfaces, including aliases of `List`, `Set`, `Map`, `Iterable`, queues, hash/tree collections, and typed-data lists |
| Constructor | One unnamed primary constructor; use `class const` when constant construction is required | Traditional, named-primary, factory-only, external, or positional forms |
| Library shape | Multiple models, generics with bounds, const/defaults, records, and ordinary parts | A generated part per model or renderer access to unresolved AST/types |

JSON generation occurs only with `@DartitectJson()`. The generator does not
create unions, DTO/entity schemas, ObjectBox entities, dependency injection,
ViewModels, routes, REST clients, runtime reflection, or mutable models. Other
generators may coexist only when they own different output files.

Missing primary constructors produce `DT1030` and no model output is applied.
Annotation identity is semantic, not a lexical name comparison. The shared
read-only compiler owns one Analyzer lifecycle and produces the same public IR,
granular `DT1030+` rules, source locations, severities, and fix IDs for the CLI
and official lints. The renderer receives only validated IR.

Run `dartitect model migrate primary` for a read-only semantic preview of
eligible traditional value classes. Only `--apply` takes the shared project
lock, writes the dedicated source journal, revalidates bytes, and commits or
rolls back the complete edit. Behavioral classes and ambiguous constructors are
reported for consumer review and are never rewritten heuristically.

## Generated equality and `copyWith`

The mixin emits abstract getters, complete `equalityFields`, and typed
`copyWith`:

| Input | Nullable field | Non-nullable field |
|---|---|---|
| Omitted | Preserve | Preserve |
| Non-null value | Replace | Replace |
| Explicit `null` | Preserve | Not a replacement |
| `clear<Field>: true` | Clear to `null` | No clear parameter exists |
| Value and clear together | Throw `ArgumentError` | Not applicable |

`ValueEquality` requires the same runtime type and compares fields in stable
declaration order. Lists are ordered; sets and maps are unordered; nested
lists, sets, and maps are structural. Records and other values use their own
equality contract. Equal values receive equal hashes. Cyclic collection graphs
throw `CyclicValueException` for equality and hashing.

Use this contract for small, immutable, acyclic values. Model fields retain
`ImmutableValueList`, `ImmutableValueSet`, or `ImmutableValueMap`; each copies
its source and exposes no mutable collection interface. Large collections,
entities, and snapshots should use identity, a version/projection, or a
precomputed hash.

## Generated JSON codecs

JSON remains independent from value equality. Generated codecs return typed
`Result` values, reject unknown keys by default, honor explicit field renames,
and never place rejected input values in `DartitectJsonFailure`. Automatic
composition is limited to JSON scalars, injected generic codecs, and Dartitect
immutable collections. Dates, enums, IDs, records, narrowing, and other
semantic conversions require an exact consumer-owned static decoder/encoder
hook pair; `DT1043` rejects missing or invalid pairs before rendering.

The default untrusted limits are depth 64, 10,000 items per collection, and
100,000 total nodes. Different bounds require `DartitectJsonLimits.custom` at
the call site. Disabling numeric limits requires either explicit annotation
metadata or `DartitectJsonLimits.trusted`; JSON shape, finite-number, and cycle
validation remain enabled. Trusted mode never changes unknown-key policy.

## Generated projections, descriptors, and mappers

`@DartitectProjection` emits typed descriptors/lenses plus an explicitly named
record selector. Selected fields are explicit and ordered; an empty field list
visibly selects all fields. Lenses reconstruct through the validated primary
constructor and do not expose a mutable interface.

`@DartitectMapper(Target)` emits a pure one-way mapper returning `Result`.
Bidirectional generation requires `bidirectional: true` and separately proven
reverse compatibility. Automatic decisions are limited to semantically
assignable, lossless scalar and immutable-collection fields. Explicit
`targetName`, `mapToWith`, and `mapFromWith` metadata owns renames and exact
static converter hooks. `DT1044` rejects an unsafe target or field before
rendering. Narrowing, enum/string, dates, IDs, relations, flattening, and
provider-owned schemas are never inferred.

## Commands, freshness, and Git ownership

| Command | Writes | Recovery | Exit behavior |
|---|---:|---:|---|
| `dartitect model sync` | No; preview by default | Reports pending recovery | 0 when fresh, 1 for findings |
| `dartitect model sync --dry-run` | No | Reports pending recovery | 0 when fresh, 1 for findings |
| `dartitect model check` | Never | Reports pending recovery | 0 when fresh, 1 for findings |
| `dartitect model sync --apply` | Yes, atomically | Recovers first, rediscovers, replans, then applies | 0 on success, 1 for model findings |
| `dartitect model migrate primary` | No; preview by default | Reports its own pending source journal | 0 when no migration remains, 1 for a preview/findings |
| `dartitect model migrate primary --apply` | Yes, atomically | Rolls back an incomplete source transaction before rediscovery | 0 on success |

Both commands accept `--json`. Global exit code 2 means usage/configuration
failure and 3 means I/O/internal failure. Preview, dry-run, and check never
repair files or recovery residue.

Commit every `*.dartitect.g.dart` and `.dartitect/model-outputs.json`. CI runs
`dartitect model check` and rejects any generated diff. A clean checkout must
analyze, test, and compile consumers without installing or invoking
`dartitect_cli`.

| Plan state | Meaning | Diagnostic/apply rule |
|---|---|---|
| `create`, `update`, `delete` | Missing, stale, or orphaned owned output | `DT1020`; apply the complete desired set |
| `noOp` | Output bytes and manifest ownership are current | Fresh; no write |
| `conflict` | Ownership cannot be proven | `DT1022`; preserve all consumer bytes and abort the transaction |
| Pending journal | Interrupted transaction requires recovery | `DT1023`; only `sync --apply` may recover |

LF is canonical for generated bytes; equivalent CRLF content is treated as
current. Paths must remain project-relative, cannot traverse symlinks or the
workspace boundary, and unmanaged/corrupt outputs are never adopted. There is
no force flag.

## Manifest, schemas, and recovery

The manifest owns only complete generated outputs and records their source,
generator version, input schema, and canonical SHA-256 input/output digests.
Updates and deletes require the existing bytes to match the recorded digest.

| Artifact | 1.0 schema | Compatibility rule |
|---|---:|---|
| Semantic model input signature | 4 | Includes library identity, capabilities, generics, defaults, types, JSON policy, projections, mapper compatibility decisions, renames, hooks, and all models in the generated part |
| JSON command report | 1 | Consumers must select the supported schema explicitly |
| `.dartitect/model-outputs.json` | 1 | Missing ownership conflicts with candidate outputs; malformed, older, or future schemas fail closed |
| `.dartitect/generation-journal.json` | 2 | Malformed, older, or future schemas stop recovery and preserve residue for diagnosis |

There is no implicit migration, downgrade, or force mode. A schema change
requires an explicit compatibility implementation and new contract evidence.

Apply stages the complete generation, persists a recovery journal, backs up
owned targets, replaces outputs, replaces the manifest, validates committed
digests, and removes transaction residue. Fault tests cover every transition.
Before commit, recovery restores exact original bytes and removes newly created
targets. After the committed phase, recovery validates the new generation and
finishes cleanup. Concurrently changed bytes are preserved and reported rather
than overwritten. Recovery and retry are idempotent.

## Frozen performance envelope

The Linux reference artifact records five cold runs per scenario. Medians and
the highest observed RSS are:

| Models | Command | Median | Peak RSS | Hard budget |
|---:|---|---:|---:|---:|
| 100 | sync | 4,761,902 µs | 725,803,008 B | 15 s / 1 GiB |
| 100 | check | 2,799,851 µs | 740,970,496 B | 15 s / 1 GiB |
| 500 | sync | 9,911,425 µs | 732,372,992 B | 60 s / 1 GiB |
| 500 | check | 6,497,860 µs | 765,853,696 B | 60 s / 1 GiB |

`dart run tool/check_model_benchmark.dart` enforces the hard budgets and the
five-run evidence. A regression above 25% or any benchmark/budget replacement
requires recorded review. The validated performance envelope ends at 500
models; larger workspaces have no 1.0 performance guarantee.

Run `dartitect model check`, `dart analyze`, package tests, and the benchmark
gate from a clean checkout. Also confirm provider-generated JSON/ObjectBox
files do not collide. Use `$dartitect-modeling` for implementation and review
guidance.
