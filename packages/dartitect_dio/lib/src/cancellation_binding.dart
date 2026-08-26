import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dio/dio.dart';

/// Creates a Dio token bound one-way to a cooperative [signal].
///
/// The returned token may be shared by multiple requests. Cancelling the
/// signal cancels it at most once. Cancelling the token directly unregisters
/// the binding and never cancels the source.
CancelToken bindCancelToken(CancellationSignal signal, {Object? reason}) {
  final binding = DioCancellationBinding(signal, reason: reason);
  unawaited(binding.token.whenCancel.whenComplete(binding.dispose));
  return binding.token;
}

/// Explicitly owned cancellation binding for one or more Dio requests.
final class DioCancellationBinding implements Disposable {
  /// Binds a token to [signal] until [dispose] or token cancellation.
  DioCancellationBinding(CancellationSignal signal, {Object? reason})
    : token = CancelToken() {
    _registration = signal.register((signalReason) {
      if (!token.isCancelled) {
        token.cancel(reason ?? signalReason ?? 'Dartitect cancellation');
      }
    });
    unawaited(token.whenCancel.whenComplete(dispose));
  }

  /// Token passed to consumer-created Dio requests.
  final CancelToken token;

  late final CancellationRegistration _registration;
  var _disposed = false;

  /// Unregisters the signal listener without cancelling either owner.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _registration.dispose();
  }
}
