import 'package:dartitect/dartitect.dart';
import 'package:flutter/widgets.dart';

/// Explicit owner of one deferred Flutter first frame.
///
/// Use a `try/finally` or register the returned owner with the bootstrap
/// composition. Both [release] and [dispose] allow the frame exactly once.
final class FirstFrameGateOwner implements Disposable {
  FirstFrameGateOwner._(this._binding);

  WidgetsBinding? _binding;

  /// Whether this owner has already allowed the deferred frame.
  bool get isReleased => _binding == null;

  /// Allows the first frame idempotently.
  void release() {
    final binding = _binding;
    if (binding == null) return;
    _binding = null;
    binding.allowFirstFrame();
  }

  /// Always releases the frame, including bootstrap failure paths.
  @override
  void dispose() => release();
}

/// First-frame deferral boundary used instead of runtime splash packages.
abstract final class FirstFrameGate {
  /// Defers [binding]'s first frame once and returns its explicit owner.
  static FirstFrameGateOwner defer(WidgetsBinding binding) {
    binding.deferFirstFrame();
    return FirstFrameGateOwner._(binding);
  }
}
