import 'package:dartitect_sync/dartitect_sync.dart';

/// A manually advanced wall clock; it never changes global time.
final class ManualClock implements SyncClock {
  /// Creates a clock starting at [initial].
  ManualClock(DateTime initial) : _current = initial;

  DateTime _current;

  /// Current fake wall-clock time.
  @override
  DateTime now() => _current.toUtc();

  /// Moves time forward by [duration].
  void advance(Duration duration) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'must not be negative');
    }
    _current = _current.add(duration);
  }

  /// Sets the clock to [value] when it does not move backwards.
  void set(DateTime value) {
    if (value.isBefore(_current)) {
      throw ArgumentError.value(value, 'value', 'must not move backwards');
    }
    _current = value;
  }
}
