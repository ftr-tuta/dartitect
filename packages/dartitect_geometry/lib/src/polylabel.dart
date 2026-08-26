import 'dart:math' as math;

import 'geometry.dart';

/// Pole of inaccessibility and its shortest distance to polygon boundaries.
final class PoleOfInaccessibility {
  /// Creates an immutable result.
  const PoleOfInaccessibility({required this.point, required this.distance});

  /// Best interior point found within the requested precision.
  final Point2<double> point;

  /// Non-negative distance from [point] to the nearest boundary.
  final double distance;
}

/// Finds a polygon's pole of inaccessibility with deterministic subdivision.
///
/// [precision] is the maximum remaining distance improvement and must be finite
/// and strictly positive. The polygon is validated by [Polygon2] before this
/// function can run.
PoleOfInaccessibility poleOfInaccessibility(
  Polygon2 polygon, {
  double precision = 1,
}) {
  if (!precision.isFinite || precision <= 0) {
    throw ArgumentError.value(
      precision,
      'precision',
      'must be finite and strictly positive',
    );
  }
  final outer = polygon.outerRing;
  var minX = outer.first.x;
  var minY = outer.first.y;
  var maxX = minX;
  var maxY = minY;
  for (final point in outer.skip(1)) {
    minX = math.min(minX, point.x);
    minY = math.min(minY, point.y);
    maxX = math.max(maxX, point.x);
    maxY = math.max(maxY, point.y);
  }
  final width = maxX - minX;
  final height = maxY - minY;
  final cellSize = math.min(width, height);
  if (cellSize <= 0) {
    throw ArgumentError('Polygon bounding box is degenerate.');
  }

  final queue = _CellHeap();
  final half = cellSize / 2;
  for (var x = minX; x < maxX; x += cellSize) {
    for (var y = minY; y < maxY; y += cellSize) {
      queue.add(_Cell(x + half, y + half, half, polygon));
    }
  }

  var best = _centroidCell(polygon);
  final boundingCell = _Cell(minX + width / 2, minY + height / 2, 0, polygon);
  if (_better(boundingCell, best)) best = boundingCell;

  while (queue.isNotEmpty) {
    final cell = queue.removeFirst();
    if (_better(cell, best)) best = cell;
    if (cell.maximum - best.distance <= precision) continue;
    final nextHalf = cell.half / 2;
    queue
      ..add(_Cell(cell.x - nextHalf, cell.y - nextHalf, nextHalf, polygon))
      ..add(_Cell(cell.x + nextHalf, cell.y - nextHalf, nextHalf, polygon))
      ..add(_Cell(cell.x - nextHalf, cell.y + nextHalf, nextHalf, polygon))
      ..add(_Cell(cell.x + nextHalf, cell.y + nextHalf, nextHalf, polygon));
  }

  return PoleOfInaccessibility(
    point: Point2<double>(best.x, best.y),
    distance: math.max(0, best.distance),
  );
}

bool _better(_Cell candidate, _Cell current) {
  if (candidate.distance != current.distance) {
    return candidate.distance > current.distance;
  }
  if (candidate.x != current.x) return candidate.x < current.x;
  return candidate.y < current.y;
}

_Cell _centroidCell(Polygon2 polygon) {
  final ring = polygon.outerRing;
  var areaScale = 0.0;
  var x = 0.0;
  var y = 0.0;
  for (var index = 0; index < ring.length; index += 1) {
    final current = ring[index];
    final next = ring[(index + 1) % ring.length];
    final cross = current.x * next.y - next.x * current.y;
    x += (current.x + next.x) * cross;
    y += (current.y + next.y) * cross;
    areaScale += cross * 3;
  }
  if (areaScale.abs() <= defaultGeometryTolerance) {
    return _Cell(ring.first.x, ring.first.y, 0, polygon);
  }
  return _Cell(x / areaScale, y / areaScale, 0, polygon);
}

final class _Cell {
  _Cell(this.x, this.y, this.half, Polygon2 polygon)
    : distance = _signedDistance(Point2<double>(x, y), polygon),
      maximum =
          _signedDistance(Point2<double>(x, y), polygon) + half * math.sqrt2;

  final double x;
  final double y;
  final double half;
  final double distance;
  final double maximum;
}

double _signedDistance(Point2<double> point, Polygon2 polygon) {
  var inside = false;
  var minimumSquared = double.infinity;
  final rings = <List<Point2<double>>>[polygon.outerRing, ...polygon.holes];
  for (var ringIndex = 0; ringIndex < rings.length; ringIndex += 1) {
    final ring = rings[ringIndex];
    var inRing = false;
    for (
      var current = 0, previous = ring.length - 1;
      current < ring.length;
      previous = current++
    ) {
      final a = ring[current];
      final b = ring[previous];
      if ((a.y > point.y) != (b.y > point.y) &&
          point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x) {
        inRing = !inRing;
      }
      minimumSquared = math.min(
        minimumSquared,
        _segmentDistanceSquared(point, a, b),
      );
    }
    if (ringIndex == 0) {
      inside = inRing;
    } else if (inRing) {
      inside = false;
    }
  }
  final distance = math.sqrt(minimumSquared);
  return inside ? distance : -distance;
}

double _segmentDistanceSquared(
  Point2<double> point,
  Point2<double> start,
  Point2<double> end,
) {
  var x = start.x;
  var y = start.y;
  final dx = end.x - x;
  final dy = end.y - y;
  if (dx != 0 || dy != 0) {
    final projection =
        ((point.x - x) * dx + (point.y - y) * dy) / (dx * dx + dy * dy);
    if (projection > 1) {
      x = end.x;
      y = end.y;
    } else if (projection > 0) {
      x += dx * projection;
      y += dy * projection;
    }
  }
  final px = point.x - x;
  final py = point.y - y;
  return px * px + py * py;
}

final class _CellHeap {
  final List<_Cell> _cells = <_Cell>[];

  bool get isNotEmpty => _cells.isNotEmpty;

  void add(_Cell cell) {
    _cells.add(cell);
    var index = _cells.length - 1;
    while (index > 0) {
      final parent = (index - 1) ~/ 2;
      if (!_higher(_cells[index], _cells[parent])) break;
      final value = _cells[index];
      _cells[index] = _cells[parent];
      _cells[parent] = value;
      index = parent;
    }
  }

  _Cell removeFirst() {
    final first = _cells.first;
    final last = _cells.removeLast();
    if (_cells.isEmpty) return first;
    _cells[0] = last;
    var index = 0;
    while (true) {
      final left = index * 2 + 1;
      final right = left + 1;
      var highest = index;
      if (left < _cells.length && _higher(_cells[left], _cells[highest])) {
        highest = left;
      }
      if (right < _cells.length && _higher(_cells[right], _cells[highest])) {
        highest = right;
      }
      if (highest == index) break;
      final value = _cells[index];
      _cells[index] = _cells[highest];
      _cells[highest] = value;
      index = highest;
    }
    return first;
  }

  static bool _higher(_Cell left, _Cell right) {
    if (left.maximum != right.maximum) return left.maximum > right.maximum;
    if (left.x != right.x) return left.x < right.x;
    if (left.y != right.y) return left.y < right.y;
    return left.half < right.half;
  }
}
