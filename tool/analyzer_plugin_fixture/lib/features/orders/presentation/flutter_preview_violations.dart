import 'package:dartitect_flutter_testing/dartitect_flutter_testing.dart' as dt;
import 'package:flutter/widgets.dart';

import '../quality_facade.dart' as quality;

@dt.DartitectPreviewMatrix()
Widget unsafePreview(String seed) {
  quality.initializeNetwork();
  return Text(seed);
}
