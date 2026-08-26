import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform tracking-authorization state without automatic prompts.
enum TrackingAuthorizationStatus {
  /// ATT is unavailable on this platform or OS version.
  notSupported,

  /// The user has not yet made a choice.
  notDetermined,

  /// System policy restricts the choice.
  restricted,

  /// The user denied tracking authorization.
  denied,

  /// The user authorized tracking.
  authorized,
}

/// Explicit tracking authorization port.
abstract interface class TrackingAuthorizationService {
  /// Reads status without showing a prompt.
  Future<TrackingAuthorizationStatus> status();

  /// Requests authorization only when called by the consumer.
  Future<TrackingAuthorizationStatus> request();
}

/// Method-channel implementation that is inert on non-iOS platforms.
final class MethodChannelTrackingAuthorizationService
    implements TrackingAuthorizationService {
  /// Creates a service without reading status or requesting authorization.
  MethodChannelTrackingAuthorizationService({
    MethodChannel? channel,
    TargetPlatform? platform,
    bool? isWeb,
  }) : _channel = channel ?? const MethodChannel(_channelName),
       _platform = platform,
       _isWeb = isWeb;

  static const String _channelName = 'dev.dartitect/privacy';

  final MethodChannel _channel;
  final TargetPlatform? _platform;
  final bool? _isWeb;

  bool get _isSupported =>
      !(_isWeb ?? kIsWeb) &&
      (_platform ?? defaultTargetPlatform) == TargetPlatform.iOS;

  @override
  Future<TrackingAuthorizationStatus> status() => _invoke('status');

  @override
  Future<TrackingAuthorizationStatus> request() => _invoke('request');

  Future<TrackingAuthorizationStatus> _invoke(String method) async {
    if (!_isSupported) return TrackingAuthorizationStatus.notSupported;
    final value = await _channel.invokeMethod<String>(method);
    return switch (value) {
      'notSupported' => TrackingAuthorizationStatus.notSupported,
      'notDetermined' => TrackingAuthorizationStatus.notDetermined,
      'restricted' => TrackingAuthorizationStatus.restricted,
      'denied' => TrackingAuthorizationStatus.denied,
      'authorized' => TrackingAuthorizationStatus.authorized,
      _ => throw PlatformException(
        code: 'invalid_status',
        message: 'Native tracking authorization returned an unknown status.',
      ),
    };
  }
}
