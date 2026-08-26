import 'package:dartitect_privacy/dartitect_privacy.dart';

Future<void> requestTrackingAfterConsumerDisclosure() async {
  final tracking = MethodChannelTrackingAuthorizationService();
  if (await tracking.status() == TrackingAuthorizationStatus.notDetermined) {
    await tracking.request();
  }
}
