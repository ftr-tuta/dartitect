/// Absolute bound used by polygon validation and boundary comparisons.
///
/// Coordinate comparisons use input units; area and orientation determinants
/// use squared input units. [Point2] equality remains exact.
const double defaultGeometryTolerance = 1e-12;

/// Immutable typed two-dimensional point with finite coordinates.
final class Point2<T extends num> {
  /// Creates a finite point.
  factory Point2(T x, T y) {
    if (!x.toDouble().isFinite || !y.toDouble().isFinite) {
      throw ArgumentError('Point coordinates must be finite.');
    }
    return Point2<T>._(x, y);
  }

  const Point2._(this.x, this.y);

  /// Horizontal coordinate.
  final T x;

  /// Vertical coordinate.
  final T y;

  /// Returns this point represented with double coordinates.
  Point2<double> toDoublePoint() => Point2<double>(x.toDouble(), y.toDouble());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Point2<T> && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Point2($x, $y)';
}

/// Immutable validated polygon with one outer ring and optional holes.
final class Polygon2 {
  /// Validates and copies [outerRing] and [holes].
  factory Polygon2({
    required Iterable<Point2<num>> outerRing,
    Iterable<Iterable<Point2<num>>> holes = const <Iterable<Point2<num>>>[],
  }) {
    final outer = _normalizeRing(outerRing, name: 'outerRing');
    final normalizedHoles = <List<Point2<double>>>[
      for (final hole in holes) _normalizeRing(hole, name: 'hole'),
    ];
    _validateSimple(outer, name: 'outerRing');
    for (final hole in normalizedHoles) {
      _validateSimple(hole, name: 'hole');
      if (_pointLocation(hole.first, outer) != _PointLocation.inside ||
          _ringsIntersect(outer, hole)) {
        throw ArgumentError(
          'Every hole must be strictly inside the outer ring.',
        );
      }
    }
    for (var left = 0; left < normalizedHoles.length; left += 1) {
      for (var right = left + 1; right < normalizedHoles.length; right += 1) {
        final first = normalizedHoles[left];
        final second = normalizedHoles[right];
        if (_ringsIntersect(first, second) ||
            _pointLocation(first.first, second) != _PointLocation.outside ||
            _pointLocation(second.first, first) != _PointLocation.outside) {
          throw ArgumentError(
            'Polygon holes must not overlap or contain one another.',
          );
        }
      }
    }
    return Polygon2._(
      List<Point2<double>>.unmodifiable(outer),
      List<List<Point2<double>>>.unmodifiable(
        normalizedHoles.map(List<Point2<double>>.unmodifiable),
      ),
    );
  }

  const Polygon2._(this.outerRing, this.holes);

  /// Outer boundary without a duplicated closing vertex.
  final List<Point2<double>> outerRing;

  /// Strictly interior, non-overlapping rings.
  final List<List<Point2<double>>> holes;
}

List<Point2<double>> _normalizeRing(
  Iterable<Point2<num>> input, {
  required String name,
}) {
  final points = <Point2<double>>[
    for (final point in input) point.toDoublePoint(),
  ];
  if (points.length >= 2 && points.first == points.last) points.removeLast();
  if (points.length < 3 || points.toSet().length < 3) {
    throw ArgumentError('$name must contain at least three distinct points.');
  }
  if (_signedArea(points).abs() <= defaultGeometryTolerance) {
    throw ArgumentError('$name is degenerate.');
  }
  return points;
}

void _validateSimple(List<Point2<double>> ring, {required String name}) {
  final length = ring.length;
  for (var left = 0; left < length; left += 1) {
    final leftNext = (left + 1) % length;
    if (ring[left] == ring[leftNext]) {
      throw ArgumentError('$name contains a zero-length edge.');
    }
    for (var right = left + 1; right < length; right += 1) {
      final rightNext = (right + 1) % length;
      final adjacent = left == right || leftNext == right || rightNext == left;
      if (!adjacent &&
          _segmentsIntersect(
            ring[left],
            ring[leftNext],
            ring[right],
            ring[rightNext],
          )) {
        throw ArgumentError('$name self-intersects.');
      }
    }
  }
}

double _signedArea(List<Point2<double>> ring) {
  var sum = 0.0;
  for (var index = 0; index < ring.length; index += 1) {
    final current = ring[index];
    final next = ring[(index + 1) % ring.length];
    sum += current.x * next.y - next.x * current.y;
  }
  return sum / 2;
}

bool _ringsIntersect(List<Point2<double>> first, List<Point2<double>> second) {
  for (var left = 0; left < first.length; left += 1) {
    for (var right = 0; right < second.length; right += 1) {
      if (_segmentsIntersect(
        first[left],
        first[(left + 1) % first.length],
        second[right],
        second[(right + 1) % second.length],
      )) {
        return true;
      }
    }
  }
  return false;
}

bool _segmentsIntersect(
  Point2<double> a,
  Point2<double> b,
  Point2<double> c,
  Point2<double> d,
) {
  final abC = _orientation(a, b, c);
  final abD = _orientation(a, b, d);
  final cdA = _orientation(c, d, a);
  final cdB = _orientation(c, d, b);
  if (abC * abD < 0 && cdA * cdB < 0) return true;
  return abC == 0 && _onSegment(a, b, c) ||
      abD == 0 && _onSegment(a, b, d) ||
      cdA == 0 && _onSegment(c, d, a) ||
      cdB == 0 && _onSegment(c, d, b);
}

int _orientation(Point2<double> a, Point2<double> b, Point2<double> c) {
  final cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
  if (cross.abs() <= defaultGeometryTolerance) return 0;
  return cross < 0 ? -1 : 1;
}

bool _onSegment(Point2<double> a, Point2<double> b, Point2<double> point) =>
    point.x >= _min(a.x, b.x) - defaultGeometryTolerance &&
    point.x <= _max(a.x, b.x) + defaultGeometryTolerance &&
    point.y >= _min(a.y, b.y) - defaultGeometryTolerance &&
    point.y <= _max(a.y, b.y) + defaultGeometryTolerance;

enum _PointLocation { outside, boundary, inside }

_PointLocation _pointLocation(Point2<double> point, List<Point2<double>> ring) {
  var inside = false;
  for (
    var current = 0, previous = ring.length - 1;
    current < ring.length;
    previous = current++
  ) {
    final a = ring[previous];
    final b = ring[current];
    if (_orientation(a, b, point) == 0 && _onSegment(a, b, point)) {
      return _PointLocation.boundary;
    }
    final crosses =
        (a.y > point.y) != (b.y > point.y) &&
        point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x;
    if (crosses) inside = !inside;
  }
  return inside ? _PointLocation.inside : _PointLocation.outside;
}

double _min(double left, double right) => left < right ? left : right;

double _max(double left, double right) => left > right ? left : right;
