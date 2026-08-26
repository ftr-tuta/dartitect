# Dartitect Geometry

[Português (Brasil)](README.pt-BR.md)

## Purpose

`dartitect_geometry` provides finite Cartesian 2D points, immutable validated
polygons with holes, and deterministic pole-of-inaccessibility subdivision.
Coordinates are planar; units are inherited from the input.

`defaultGeometryTolerance` is the explicit absolute `1e-12` comparison bound.
It is used in coordinate-unit boundary comparisons and squared-input-unit area
and orientation determinants. Point equality remains exact. `precision` is in
input units, must be finite and positive, and bounds the remaining possible
distance improvement when subdivision stops; its default is `1`.

## Boundary contract

- Why a package: isolate optional planar algorithms and attribution from core.
- Owns: immutable copies of polygon coordinates; borrows/persists nothing.
- Logs: nothing; coordinates and results never enter telemetry.
- Supports: finite planar 2D points, simple outer rings, non-overlapping holes,
  deterministic polylabel, explicit tolerance, and explicit precision.
- Does not support: GIS, CRS, projection, geodesy, special latitude/longitude,
  antimeridian behavior, units conversion, or topology repair.
- Removal: remove the package and replace calls at the geometry adapter; no
  stored format or runtime resource requires migration.

## Attribution

The subdivision approach is derived from Mapbox polylabel. Its ISC attribution
is preserved in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
