import 'logging.dart';

/// Determines whether a sanitized event should be dispatched.
abstract interface class SamplingPolicy {
  /// Returns true when a log should be retained.
  bool shouldSampleLog(LogEvent event);

  /// Returns true when a span should be recorded.
  bool shouldSampleSpan(String name);
}

/// Deterministic all-or-nothing local policy.
///
/// Error and fatal logs are always retained regardless of [logRate].
final class FixedSamplingPolicy implements SamplingPolicy {
  /// Creates a fixed policy. Rates must be from zero through one.
  FixedSamplingPolicy({this.logRate = 1, this.spanRate = 0}) {
    if (logRate < 0 || logRate > 1 || spanRate < 0 || spanRate > 1) {
      throw RangeError('Sampling rates must be between 0 and 1.');
    }
  }

  /// Retention rate for trace through warning logs.
  final double logRate;

  /// Recording rate for spans.
  final double spanRate;

  var _logCounter = 0;
  var _spanCounter = 0;

  @override
  bool shouldSampleLog(LogEvent event) {
    if (event.level.index >= LogLevel.error.index) return true;
    return _sample(logRate, _logCounter++);
  }

  @override
  bool shouldSampleSpan(String name) => _sample(spanRate, _spanCounter++);

  static bool _sample(double rate, int counter) {
    if (rate <= 0) return false;
    if (rate >= 1) return true;
    final bucket = counter % 10000;
    return bucket < (rate * 10000).round();
  }
}
