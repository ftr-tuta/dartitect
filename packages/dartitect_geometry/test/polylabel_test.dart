import 'package:dartitect_geometry/dartitect_geometry.dart';
import 'package:test/test.dart';

void main() {
  test('finds the reference center of a square deterministically', () {
    final polygon = Polygon2(
      outerRing: _ring(<(double, double)>[(0, 0), (10, 0), (10, 10), (0, 10)]),
    );
    final first = poleOfInaccessibility(polygon, precision: 0.001);
    final second = poleOfInaccessibility(polygon, precision: 0.001);
    expect(first.point.x, closeTo(5, 0.001));
    expect(first.point.y, closeTo(5, 0.001));
    expect(first.distance, closeTo(5, 0.001));
    expect(second.point, first.point);
    expect(second.distance, first.distance);
  });

  test('respects holes and narrow polygons', () {
    final withHole = Polygon2(
      outerRing: _ring(<(double, double)>[(0, 0), (20, 0), (20, 20), (0, 20)]),
      holes: <List<Point2<double>>>[
        _ring(<(double, double)>[(8, 8), (12, 8), (12, 12), (8, 12)]),
      ],
    );
    final result = poleOfInaccessibility(withHole, precision: 0.01);
    expect(result.distance, greaterThan(4));
    expect(result.point.x < 8 || result.point.x > 12, isTrue);

    final narrow = Polygon2(
      outerRing: _ring(<(double, double)>[(0, 0), (100, 0), (100, 1), (0, 1)]),
    );
    final narrowResult = poleOfInaccessibility(narrow, precision: 0.001);
    expect(narrowResult.point.y, closeTo(0.5, 0.001));
    expect(narrowResult.distance, closeTo(0.5, 0.001));
  });

  test('rejects invalid precision, coordinates, rings, and topology', () {
    expect(defaultGeometryTolerance, 1e-12);
    expect(() => Point2<double>(double.nan, 0), throwsArgumentError);
    expect(
      () => Polygon2(
        outerRing: _ring(<(double, double)>[(0, 0), (1, 1), (2, 2)]),
      ),
      throwsArgumentError,
    );
    expect(
      () => Polygon2(
        outerRing: _ring(<(double, double)>[
          (0, 0),
          (10, 10),
          (0, 10),
          (10, 0),
        ]),
      ),
      throwsArgumentError,
    );
    expect(
      () => Polygon2(
        outerRing: _ring(<(double, double)>[
          (0, 0),
          (10, 0),
          (10, 10),
          (0, 10),
        ]),
        holes: <List<Point2<double>>>[
          _ring(<(double, double)>[(8, 8), (12, 8), (12, 12), (8, 12)]),
        ],
      ),
      throwsArgumentError,
    );
    final valid = Polygon2(
      outerRing: _ring(<(double, double)>[(0, 0), (1, 0), (1, 1), (0, 1)]),
    );
    expect(
      () => poleOfInaccessibility(valid, precision: 0),
      throwsArgumentError,
    );
  });

  test('applies the documented absolute degeneracy tolerance', () {
    expect(
      () => Polygon2(
        outerRing: _ring(<(double, double)>[
          (0, 0),
          (1, 0),
          (0, defaultGeometryTolerance * 2),
        ]),
      ),
      throwsArgumentError,
    );
    expect(
      Polygon2(
        outerRing: _ring(<(double, double)>[
          (0, 0),
          (1, 0),
          (0, defaultGeometryTolerance * 4),
        ]),
      ).outerRing,
      hasLength(3),
    );
  });

  test('owns immutable coordinate copies without retaining inputs', () {
    final outer = _ring(<(double, double)>[(0, 0), (10, 0), (10, 10), (0, 10)]);
    final hole = _ring(<(double, double)>[(2, 2), (3, 2), (3, 3), (2, 3)]);
    final polygon = Polygon2(
      outerRing: outer,
      holes: <List<Point2<double>>>[hole],
    );

    outer[0] = Point2<double>(100, 100);
    hole[0] = Point2<double>(200, 200);
    expect(polygon.outerRing.first, Point2<double>(0, 0));
    expect(polygon.holes.single.first, Point2<double>(2, 2));
    expect(
      () => polygon.outerRing.add(Point2<double>(1, 1)),
      throwsUnsupportedError,
    );
    expect(
      () => polygon.holes.single.add(Point2<double>(1, 1)),
      throwsUnsupportedError,
    );
  });
}

List<Point2<double>> _ring(List<(double, double)> coordinates) =>
    <Point2<double>>[
      for (final coordinate in coordinates)
        Point2<double>(coordinate.$1, coordinate.$2),
    ];
