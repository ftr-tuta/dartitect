import 'dart:async';

/// Manually advanced monotonic scheduler for retry/debounce/deadline tests.
final class ManualScheduler {
  var _elapsed = Duration.zero;
  final List<_ScheduledDelay> _delays = <_ScheduledDelay>[];

  /// Current monotonic elapsed duration.
  Duration get elapsed => _elapsed;

  /// Number of unresolved delays.
  int get pendingCount => _delays.length;

  /// Delay callback compatible with injected retry wait functions.
  Future<void> wait(Duration duration) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'must not be negative');
    }
    if (duration == Duration.zero) return Future<void>.value();
    final delay = _ScheduledDelay(_elapsed + duration);
    _delays.add(delay);
    _delays.sort((left, right) => left.due.compareTo(right.due));
    return delay.completer.future;
  }

  /// Advances time and completes due delays in stable creation order.
  void advance(Duration duration) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'must not be negative');
    }
    _elapsed += duration;
    final due = _delays
        .where((delay) => delay.due <= _elapsed)
        .toList(growable: false);
    _delays.removeWhere((delay) => delay.due <= _elapsed);
    for (final delay in due) {
      delay.completer.complete();
    }
  }
}

final class _ScheduledDelay {
  _ScheduledDelay(this.due);

  final Duration due;
  final Completer<void> completer = Completer<void>();
}
