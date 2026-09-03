# dartitect_geometry

## Purpose

Dependency-free finite Cartesian 2D points, immutable validated polygons with
holes, and deterministic pole-of-inaccessibility subdivision for a label anchor.

## When to use

Use it when an application already has planar coordinates and needs a validated
simple polygon plus a deterministic interior point far from its boundaries.

## When not to use

Do not use it for GIS, coordinate reference systems, projections, geodesy,
latitude/longitude semantics, antimeridian handling, unit conversion, mutable
geometry, boolean topology, or topology repair.

## Platforms and entrypoints

Import `package:dartitect_geometry/dartitect_geometry.dart`. It is
dependency-free pure Dart and supports the Dart VM, Flutter, and web.

## Mental model and data flow

The consumer supplies finite planar `Point2` values in one consistent input
unit. `Polygon2` copies and validates the outer ring and holes. The
`poleOfInaccessibility` function subdivides deterministically until `precision`
bounds the remaining possible distance improvement, returning a point and its
distance from polygon boundaries.

## Minimal workflow

```dart
import 'package:dartitect_geometry/dartitect_geometry.dart';

void main() {
  final polygon = Polygon2(
    outerRing: <Point2<double>>[
      Point2<double>(0, 0),
      Point2<double>(10, 0),
      Point2<double>(10, 10),
      Point2<double>(0, 10),
    ],
  );
  final result = poleOfInaccessibility(polygon, precision: 0.01);
  assert(result.point == Point2<double>(5, 5));
}
```

## Public API tour

- `Point2<N extends num>` is an immutable exact-equality Cartesian point.
- `Polygon2` copies/validates a simple outer ring and non-overlapping holes.
- `PoleOfInaccessibility` contains the selected point and boundary distance.
- `poleOfInaccessibility` performs deterministic subdivision.
- `defaultGeometryTolerance` is the explicit absolute `1e-12` comparison bound.

## Ownership and lifecycle

Points/results are immutable. Polygon construction copies and freezes ring
coordinates. The package borrows and persists nothing and has no resource
lifecycle.

## Failure, cancellation, and concurrency

Construction and calculation are synchronous and deterministic. Invalid,
non-finite, degenerate, self-intersecting, touching/outside, overlapping, or
nested-hole inputs fail validation. `precision` must be finite and positive.
There is no cancellation or internal concurrency; callers choose an explicit
isolate projection for expensive inputs.

## Prohibited uses and limitations

Coordinates are planar and unitless; output inherits input units. Point equality
is exact. The tolerance applies to boundary comparisons and area/orientation
determinants in their corresponding input units. The algorithm does not repair
topology or interpret map coordinates. Never emit coordinates/results as
telemetry through this package.

## Testing

Run `dart test`. Cover invalid topology, holes, finite-number requirements,
tolerance/precision boundaries, determinism, translation/scale invariants,
known label anchors, and fuzz cases on VM and web where consumed.

## Related packages and guides

Use a consumer adapter to project geographic data into a suitable planar system
before calling this package. Read
[optional capabilities](../../docs/guides/optional-capabilities.md) and
[ecosystem selection](../../docs/guides/ecosystem-selection.md). The Mapbox
polylabel-derived approach retains its ISC notice in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Availability

Dartitect `1.1.0` is distributed only by the annotated `v1.1.0` tag and
its immutable GitHub Release. Declare this package directly with the canonical
Git descriptor; its transitive Dartitect dependencies resolve from the same tag
without overrides. See the
[Git release consumption guide](../../docs/guides/git-release-consumption.md).
