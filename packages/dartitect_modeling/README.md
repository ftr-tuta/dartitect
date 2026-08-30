# dartitect_modeling

## Purpose

Pure-Dart, web-compatible immutable modeling primitives: value annotations,
copied immutable collections, bounded JSON codecs, projections/lenses, and
lossless boundary mappers. Capabilities are opt-in and do not select a provider
schema or runtime architecture.

## When to use

Use it when a model boundary needs explicit value semantics, defensive immutable
collections, bounded untrusted JSON, generated projections, or a typed
lossless mapper whose behavior is reviewable.

## When not to use

Do not use it to infer dates, identifiers, enums, relations, normalization,
database entities, or lossy conversions. It is not a reflection runtime,
serializer for arbitrary object graphs, ORM model generator, or replacement for
consumer-owned validation.

## Platforms and entrypoints

Import `package:dartitect_modeling/dartitect_modeling.dart`. The package is pure
Dart and supports the Dart VM, Flutter, and web.

## Mental model and data flow

The consumer declares each capability separately with `@DartitectValue`,
`@DartitectJson`, `@DartitectProjection`, or `@DartitectMapper`. Source models
and semantic conversion hooks remain consumer-owned. Code generation resolves
types statically and produces explicit codecs, selectors, lenses, and mappers.
Untrusted values enter through bounded codecs and leave as `Result`, never as an
unchecked cast or payload-bearing diagnostic.

## Minimal workflow

```dart
import 'package:dartitect_modeling/dartitect_modeling.dart';

@DartitectValue()
final class const Profile({
  required final String id,
  final String? displayName,
}) extends ValueEquality {
  this;

  @override
  Iterable<Object?> get equalityFields => <Object?>[id, displayName];
}

void main() {
  assert(
    const Profile(id: '1', displayName: 'Ada') ==
        const Profile(id: '1', displayName: 'Ada'),
  );
}
```

## Public API tour

- `DartitectValue`, `ValueEquality`, and `ImmutableValueList`,
  `ImmutableValueSet`, and `ImmutableValueMap` implement explicit value
  semantics with copied containers.
- `DartitectJsonCodec`, `DartitectJsonCodecs`, scalar codecs, collection codecs,
  `DartitectJsonLimits`, `DartitectUnknownKeys`, and typed path/failure objects
  define bounded JSON boundaries.
- `DartitectProjection`, `DartitectProjectionSelector`,
  `DartitectFieldDescriptor`, and `DartitectLens` define generated named-record
  projections and immutable reconstruction.
- `DartitectMapper`, `DartitectField`, boundary mapper interfaces, hook typedefs,
  and `DartitectMappingFailure` define explicit forward and optional reverse
  mapping.
- The package re-exports only the core result/value members required to use
  these APIs.

## Ownership and lifecycle

Model values and immutable collections own copied data and have no disposal
lifecycle. Generated files are manifest-owned by Dartitect tooling; application
models and custom hooks are consumer-owned. Do not edit fully generated outputs
by hand.

## Failure, cancellation, and concurrency

JSON decoding and mapping return typed `Result` failures with structural
key/index or declared-field paths. Failures never retain rejected payloads.
There is no cancellation or asynchronous execution in this package. Generated
operations are pure and safe to call concurrently when consumer hooks are pure.

Untrusted traversal defaults to maximum depth 64, 10,000 items per collection,
and 100,000 total nodes. `DartitectJsonLimits.trusted` disables numeric limits
visibly, but shape, finite-number, and cycle checks remain active.

## Prohibited uses and limitations

- No inferred narrowing, enum/string, date, identifier, relation, or flattening.
- No provider schema or generated database entity ownership.
- No mutable collection interface or cyclic nested collection graph.
- No unknown JSON keys by default.
- No bidirectional mapper unless every reverse field is independently lossless.

Use consumer-owned static encode/decode or mapping hooks for semantic
conversion.

## Testing

Run `dart test`. Test equality/hash behavior, copied collection isolation,
unknown keys, numeric parity on VM/web, traversal limits, generated selectors
and lenses, expected mapping paths, and bidirectional round trips where enabled.
Use the projection and mapper harnesses from `dartitect_testing`.

## Related packages and guides

`dartitect_modeling_analyzer` exposes the read-only semantic compiler used by
tooling. `dartitect_cli` performs generation and migration; `dartitect_lints`
provides analyzer feedback. Read
[model generation](../../docs/guides/model-generation.md) and
[ecosystem selection](../../docs/guides/ecosystem-selection.md).

## Availability

The workspace contains the `1.0.0-rc.9` source candidate. Use only coordinates
published in the notes of a corresponding tagged GitHub Release; otherwise
there is no supported consumption path. See the
[Git candidate consumption guide](../../docs/guides/git-candidate-consumption.md).
