import 'package:dartitect_media/dartitect_media.dart';
import 'package:flutter_test/flutter_test.dart';

import '../example/dartitect_media_example.dart';

void main() {
  test('example projects every native capability state without I/O', () {
    expect(<GalleryCapabilityView>{
      for (final status in GalleryPermissionStatus.values)
        projectGalleryStatus(status),
      projectGalleryFailure(const GalleryNativeFailure('provider_failed')),
    }, GalleryCapabilityView.values.toSet());
  });
}
