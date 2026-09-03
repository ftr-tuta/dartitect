import 'package:dartitect_privacy/dartitect_privacy.dart';

/// Pure presentation projection for every tracking capability outcome.
enum TrackingCapabilityView {
  /// The capability can execute.
  supported,

  /// The host cannot provide the capability.
  unsupported,

  /// A consumer-owned permission interaction is required.
  permissionRequired,

  /// The user or system denied permission.
  permissionDenied,

  /// The capability may become available without an app upgrade.
  temporarilyUnavailable,

  /// The provider failed independently of permission state.
  providerFailure,
}

/// Maps status to pure view data without invoking a plugin.
TrackingCapabilityView projectTrackingStatus(
  TrackingAuthorizationStatus status,
) => switch (status) {
  TrackingAuthorizationStatus.authorized => TrackingCapabilityView.supported,
  TrackingAuthorizationStatus.notSupported =>
    TrackingCapabilityView.unsupported,
  TrackingAuthorizationStatus.notDetermined =>
    TrackingCapabilityView.permissionRequired,
  TrackingAuthorizationStatus.restricted ||
  TrackingAuthorizationStatus.denied => TrackingCapabilityView.permissionDenied,
};

/// Projects temporary/provider availability without retaining native errors.
TrackingCapabilityView projectTrackingAvailability({
  required bool temporarilyUnavailable,
  required bool providerFailed,
}) {
  if (providerFailed) return TrackingCapabilityView.providerFailure;
  if (temporarilyUnavailable) {
    return TrackingCapabilityView.temporarilyUnavailable;
  }
  return TrackingCapabilityView.supported;
}

Future<void> requestTrackingAfterConsumerDisclosure() async {
  final tracking = MethodChannelTrackingAuthorizationService();
  if (await tracking.status() == TrackingAuthorizationStatus.notDetermined) {
    await tracking.request();
  }
}
