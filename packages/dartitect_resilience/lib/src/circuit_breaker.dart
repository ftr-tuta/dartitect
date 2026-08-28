import 'package:dartitect/dartitect.dart';

import 'retry.dart';

/// Observable circuit breaker state.
enum CircuitBreakerState {
  /// Calls are admitted.
  closed,

  /// Calls are rejected until the reset interval elapses.
  open,

  /// Exactly one recovery probe is admitted.
  halfOpen,
}

/// Rejection while a circuit is open or already probing.
final class CircuitBreakerOpenException implements Exception {
  /// Creates an open-circuit rejection.
  const CircuitBreakerOpenException();
}

/// Bounded expected-failure circuit breaker.
final class CircuitBreaker {
  /// Creates a breaker with an explicit threshold and reset interval.
  CircuitBreaker({
    this.failureThreshold = 5,
    this.resetAfter = const Duration(seconds: 30),
    ResilienceClock clock = const SystemResilienceClock(),
  }) : _clock = clock {
    if (failureThreshold <= 0 || resetAfter <= Duration.zero) {
      throw ArgumentError('Circuit breaker bounds must be positive.');
    }
  }

  /// Consecutive classified failures required to open.
  final int failureThreshold;

  /// Delay before one half-open probe.
  final Duration resetAfter;

  final ResilienceClock _clock;
  var _state = CircuitBreakerState.closed;
  var _failureCount = 0;
  DateTime? _openedAt;
  var _probeActive = false;

  /// Current state after applying the clock-based open transition.
  CircuitBreakerState get state {
    _refreshState();
    return _state;
  }

  /// Current consecutive classified failure count.
  int get failureCount => _failureCount;

  /// Executes [operation], classifying only an expected [Err].
  Future<Result<T, F>> execute<T, F extends Object>({
    required Future<Result<T, F>> Function() operation,
    required bool Function(F failure) countsAsFailure,
  }) async {
    _refreshState();
    if (_state == CircuitBreakerState.open ||
        _state == CircuitBreakerState.halfOpen && _probeActive) {
      throw const CircuitBreakerOpenException();
    }
    final probe = _state == CircuitBreakerState.halfOpen;
    if (probe) _probeActive = true;
    try {
      final result = await operation();
      switch (result) {
        case Ok<dynamic>():
          _close();
        case Err<Object>(:final failure):
          if (countsAsFailure(failure as F)) {
            _recordFailure(probe: probe);
          } else if (probe) {
            _close();
          }
      }
      return result;
    } finally {
      if (probe) _probeActive = false;
    }
  }

  /// Closes the breaker and clears failure history explicitly.
  void reset() => _close();

  void _recordFailure({required bool probe}) {
    _failureCount += 1;
    if (probe || _failureCount >= failureThreshold) {
      _state = CircuitBreakerState.open;
      _openedAt = _clock.now().toUtc();
    }
  }

  void _refreshState() {
    final opened = _openedAt;
    if (_state == CircuitBreakerState.open &&
        opened != null &&
        !_clock.now().toUtc().isBefore(opened.add(resetAfter))) {
      _state = CircuitBreakerState.halfOpen;
      _probeActive = false;
    }
  }

  void _close() {
    _state = CircuitBreakerState.closed;
    _failureCount = 0;
    _openedAt = null;
    _probeActive = false;
  }
}
