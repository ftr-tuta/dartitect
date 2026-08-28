# dartitect_modeling

[Português (Brasil)](README.pt-BR.md)

## Purpose

Pure-Dart, web-compatible immutable modeling primitives for Dartitect. Import
this package to opt into values, JSON codecs, projections, or boundary mappers.
Each capability requires its own annotation; provider schemas and runtime
application architecture remain consumer-owned.

## Immutable collections

`ImmutableValueList`, `ImmutableValueSet`, and `ImmutableValueMap` copy their
source container, expose read operations without implementing a mutable
collection interface, and use structural equality and hashing. Cyclic nested
collection graphs are rejected during construction.

## JSON boundaries

`DartitectJsonCodec<T>` returns `Result` and `DartitectJsonFailure`; failures
contain a typed kind and key/index path, never the rejected value. Explicit
scalar codecs and immutable-collection combinators are available through
`DartitectJsonCodecs`. Generated codecs reject unknown object keys by default.
Integer decoding uses mathematical integrality so VM and Dart Web agree;
double decoding widens integers only when the value is preserved.

Untrusted traversal is the default and permits at most depth 64, 10,000 items
in any collection, and 100,000 total nodes. A different boundary must pass
`DartitectJsonLimits.custom`; disabling numeric limits requires the visibly
explicit `DartitectJsonLimits.trusted`. Shape, finite-number, and cycle checks
remain active in trusted mode.

The generator handles only lossless scalar, generic-codec, and immutable
collection composition. Dates, enums, identifiers, records, narrowing, and
other semantic conversions require a consumer-owned static decoder/encoder
pair named by `DartitectField`.

## Projections and lenses

`@DartitectProjection(name: ..., fields: ...)` generates a named-record typedef,
a pure selector, and typed field descriptors/lenses. An empty `fields` list
selects every primary-constructor field; otherwise declaration order is the
explicit list order. A lens reconstructs the immutable model and never exposes
mutation or reflection. Projection support does not enable value equality,
JSON, or mappers.

## Boundary mappers

`@DartitectMapper(Target)` generates a pure mapper returning
`Result<Target, DartitectMappingFailure>`. Set `bidirectional: true` only when
every reverse field is independently lossless. `DartitectField(targetName: ...)`
is the only automatic rename metadata. Exact consumer-owned static
`mapToWith`/`mapFromWith` hooks make semantic conversion visible and retain a
payload-free declared-field path on expected failures.

Automatic mapping is restricted to semantically assignable, lossless scalars
and Dartitect immutable collections. Narrowing, enum/string, dates, IDs,
relations, flattening, and provider schemas are never inferred. Mapper targets
and hooks remain consumer-owned.
