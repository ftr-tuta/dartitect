import 'retry.dart';

/// Bounded token-bucket rate limiter without hidden timers or queues.
final class RateLimiter {
  /// Creates a token bucket initially filled to [capacity].
  RateLimiter({
    required this.capacity,
    required this.refillTokens,
    required this.refillPeriod,
    ResilienceClock clock = const SystemResilienceClock(),
  }) : _clock = clock,
       _tokens = capacity.toDouble(),
       _lastRefill = clock.now().toUtc() {
    if (capacity <= 0 || refillTokens <= 0 || refillPeriod <= Duration.zero) {
      throw ArgumentError('Rate limiter bounds must be positive.');
    }
  }

  /// Maximum available tokens.
  final int capacity;

  /// Tokens added per [refillPeriod].
  final int refillTokens;

  /// Refill interval.
  final Duration refillPeriod;

  final ResilienceClock _clock;
  double _tokens;
  DateTime _lastRefill;

  /// Whole tokens currently available after clock-based refill.
  int get availableTokens {
    _refill();
    return _tokens.floor();
  }

  /// Acquires [permits] immediately or returns `false` without queueing.
  bool tryAcquire([int permits = 1]) {
    if (permits <= 0 || permits > capacity) {
      throw ArgumentError.value(
        permits,
        'permits',
        'Must be positive and no greater than capacity.',
      );
    }
    _refill();
    if (_tokens < permits) return false;
    _tokens -= permits;
    return true;
  }

  void _refill() {
    final now = _clock.now().toUtc();
    final elapsed = now.difference(_lastRefill);
    if (elapsed <= Duration.zero) return;
    final periods = elapsed.inMicroseconds ~/ refillPeriod.inMicroseconds;
    if (periods <= 0) return;
    _tokens = periods >= (capacity - _tokens) / refillTokens
        ? capacity.toDouble()
        : _tokens + periods.toDouble() * refillTokens;
    _lastRefill = now.subtract(
      Duration(
        microseconds: elapsed.inMicroseconds % refillPeriod.inMicroseconds,
      ),
    );
  }
}
