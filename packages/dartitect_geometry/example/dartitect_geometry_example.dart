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
  final labelAnchor = poleOfInaccessibility(polygon, precision: 0.01).point;
  assert(labelAnchor == Point2<double>(5, 5));
}
