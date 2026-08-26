import 'dart:math';

import 'package:dartitect_geometry/dartitect_geometry.dart';
import 'package:test/test.dart';

const _seed = 11002;
const _cases = 256;
const _precision = 0.001;

void main() {
  test(
    'deterministic rectangle and hole fuzz stays valid and translatable',
    () {
      final random = Random(_seed);
      for (var index = 0; index < _cases; index += 1) {
        final x = random.nextDouble() * 2000 - 1000;
        final y = random.nextDouble() * 2000 - 1000;
        final width = random.nextDouble() * 98 + 2;
        final height = random.nextDouble() * 98 + 2;
        final withHole = index.isOdd;
        final holes = <List<Point2<double>>>[];
        _Rect? hole;
        if (withHole) {
          final marginX = width * (0.15 + random.nextDouble() * 0.15);
          final marginY = height * (0.15 + random.nextDouble() * 0.15);
          hole = _Rect(
            x + marginX,
            y + marginY,
            x + width - marginX,
            y + height - marginY,
          );
          holes.add(_ring(hole));
        }
        final outer = _Rect(x, y, x + width, y + height);
        final polygon = Polygon2(outerRing: _ring(outer), holes: holes);
        final first = poleOfInaccessibility(polygon, precision: _precision);
        final repeated = poleOfInaccessibility(polygon, precision: _precision);

        expect(first.point, repeated.point, reason: 'seed=$_seed case=$index');
        expect(first.distance, repeated.distance, reason: 'case=$index');
        expect(first.point.x, inInclusiveRange(outer.left, outer.right));
        expect(first.point.y, inInclusiveRange(outer.top, outer.bottom));
        if (hole != null) {
          expect(
            _strictlyInside(first.point, hole),
            isFalse,
            reason: 'case=$index',
          );
        }
        expect(first.distance.isFinite, isTrue);
        expect(first.distance, greaterThan(0));

        final dx = random.nextDouble() * 20 - 10;
        final dy = random.nextDouble() * 20 - 10;
        final translated = poleOfInaccessibility(
          Polygon2(
            outerRing: _ring(outer.translate(dx, dy)),
            holes: <List<Point2<double>>>[
              if (hole != null) _ring(hole.translate(dx, dy)),
            ],
          ),
          precision: _precision,
        );
        expect(
          translated.point.x,
          inInclusiveRange(outer.left + dx, outer.right + dx),
        );
        expect(
          translated.point.y,
          inInclusiveRange(outer.top + dy, outer.bottom + dy),
        );
        if (hole != null) {
          expect(
            _strictlyInside(translated.point, hole.translate(dx, dy)),
            isFalse,
          );
        }
        expect(translated.distance, closeTo(first.distance, _precision * 2));
      }
    },
  );

  test('deterministic malformed polygon fuzz fails closed', () {
    final random = Random(_seed + 1);
    for (var index = 0; index < _cases; index += 1) {
      final offset = random.nextDouble() * 100;
      final extent = random.nextDouble() * 50 + 1;
      expect(
        () => Polygon2(
          outerRing: <Point2<double>>[
            Point2<double>(offset, offset),
            Point2<double>(offset + extent, offset + extent),
            Point2<double>(offset, offset + extent),
            Point2<double>(offset + extent, offset),
          ],
        ),
        throwsArgumentError,
        reason: 'self-intersection seed=$_seed case=$index',
      );
      expect(
        () => Polygon2(
          outerRing: _ring(_Rect(0, 0, extent, extent)),
          holes: <List<Point2<double>>>[
            _ring(_Rect(extent + 1, extent + 1, extent + 2, extent + 2)),
          ],
        ),
        throwsArgumentError,
        reason: 'outside hole seed=$_seed case=$index',
      );
    }
  });
}

bool _strictlyInside(Point2<double> point, _Rect rectangle) =>
    point.x > rectangle.left &&
    point.x < rectangle.right &&
    point.y > rectangle.top &&
    point.y < rectangle.bottom;

List<Point2<double>> _ring(_Rect rectangle) => <Point2<double>>[
  Point2<double>(rectangle.left, rectangle.top),
  Point2<double>(rectangle.right, rectangle.top),
  Point2<double>(rectangle.right, rectangle.bottom),
  Point2<double>(rectangle.left, rectangle.bottom),
];

final class _Rect {
  const _Rect(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  _Rect translate(double dx, double dy) =>
      _Rect(left + dx, top + dy, right + dx, bottom + dy);
}
