import 'package:dartitect_privacy/dartitect_privacy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../example/dartitect_privacy_example.dart';

void main() {
  test('example projects every native capability state without I/O', () {
    expect(<TrackingCapabilityView>{
      for (final status in TrackingAuthorizationStatus.values)
        projectTrackingStatus(status),
      projectTrackingAvailability(
        temporarilyUnavailable: true,
        providerFailed: false,
      ),
      projectTrackingAvailability(
        temporarilyUnavailable: false,
        providerFailed: true,
      ),
    }, TrackingCapabilityView.values.toSet());
  });
}
