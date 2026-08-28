# Dartitect model generation

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

Provider-owned mutable entities remain outside Dartitect model ownership. They
may use primary constructors with declaring `var` parameters. A traditional
provider constructor is denied unless the exact provider/generator version has
specific generator or runtime evidence in
`tool/provider_constructor_evidence.json`. ObjectBox 5.3.2 currently has the
only scoped exception: its generator resolves Analyzer 10.2.0/language 3.12 and
rejects the otherwise-valid Dart 3.13 primary candidate. Any provider upgrade
requires this evidence to be rerun; the exception never applies to immutable
Dartitect models.

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

Commit every `*.dartitect.g.dart` and
`.dartitect/generation/modeling/manifest.json`. CI runs
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

The namespaced manifest owns only complete generated outputs and records their
source, renderer version, semantic schema, and canonical SHA-256 input/output
digests. Updates and deletes require the existing bytes to match the recorded
digest. Release, protocol, semantic schema, renderer, manifest, command-report,
output-journal, and source-journal versions evolve independently; the package
release is never an ownership key or generated header.

| Artifact | 1.0 schema | Compatibility rule |
|---|---:|---|
| Semantic model input signature | 4 | Includes library identity, capabilities, generics, defaults, types, JSON policy, projections, mapper compatibility decisions, renames, hooks, and all models in the generated part |
| JSON command report | 1 | Consumers must select the supported schema explicitly |
| `.dartitect/generation/modeling/manifest.json` | 2 | Namespace and protocol must match; missing ownership conflicts with candidate outputs; malformed, older, or future schemas fail closed |
| `.dartitect/generation/modeling/journal.json` | 3 | Namespace and protocol must match; malformed schemas stop recovery and preserve residue for diagnosis |
| `.dartitect/generation/model-primary-migration/source-journal.json` | 2 | Source edits use their own namespace and transaction but the same project lock |

The only legacy adoption path is the explicit RC3 compatibility implementation:
`.dartitect/model-outputs.json` schema 1 is migrated atomically only when its
generator identity is exactly `1.0.0-rc.3` and every current canonical output
digest matches. The legacy output journal schema 2 and source journal schema 1
are recoverable at their original paths. Any mismatch, ambiguous old/new
artifact pair, downgrade, or force attempt fails closed without writes.

Each `GenerationNamespace` has an isolated manifest, journal, and transaction
directory. Generated-once scaffolds use `scaffolding`; model parts use
`modeling`. All namespaces and semantic source edits share
`.dartitect/project.lock`, including in-process serialization.

Apply stages the complete generation, persists a recovery journal, backs up
owned targets, replaces outputs, replaces the manifest, validates committed
digests, and removes transaction residue. Fault tests cover every transition.
Before commit, recovery restores exact original bytes and removes newly created
targets. After the committed phase, recovery validates the new generation and
finishes cleanup. Concurrently changed bytes are preserved and reported rather
than overwritten. Recovery and retry are idempotent.

## Frozen performance envelope

`tool/model_benchmark.json` compares exact baseline `2a8261a` and modular RC5
commit `0057db5` on the same Linux/Dart 3.13.1/4-CPU host. Each matrix cell has
five isolated cold runs (median and peak RSS) and twenty same-process warm runs
(p95 and peak RSS). Warm sync alternates one semantic field change; cache is
discardable and never ownership authority.

| Models | Command | RC5 cold median | RC5 cold RSS | RC5 warm p95 | RC5 warm RSS |
|---:|---|---:|---:|---:|---:|
| 100 | sync | 3,564,654 µs | 728,629,248 B | 1,869,518 µs | 811,585,536 B |
| 100 | check | 2,274,713 µs | 776,019,968 B | 1,914,912 µs | 803,418,112 B |
| 500 | sync | 6,907,795 µs | 813,146,112 B | 4,761,429 µs | 844,062,720 B |
| 500 | check | 6,043,847 µs | 803,332,096 B | 4,125,455 µs | 847,642,624 B |

Against the same-host legacy baseline, cold medians improved by 20.5–27.5%
and warm p95 improved by 20.6–34.3%. The largest RSS increase was 5.43%, at
500-model warm sync. `dart run tool/check_model_benchmark.dart` recomputes the
comparison, enforces the 15/60-second and 1-GiB hard budgets, and blocks any
latency or RSS regression above 10% without recorded approval. The validated
envelope ends at 500 models; larger workspaces have no 1.0 guarantee.

Run `dartitect model check`, `dart analyze`, package tests, and the benchmark
gate from a clean checkout. Also confirm provider-generated JSON/ObjectBox
files do not collide. Use `$dartitect-modeling` for implementation and review
guidance.
