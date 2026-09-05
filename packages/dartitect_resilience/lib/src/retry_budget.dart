import 'bulkhead.dart';
import 'rate_limiter.dart';
import 'retry.dart';

/// Explicit reason an attempt was refused before executing consumer work.
enum RetryBudgetStop {
  /// The shared attempt count was consumed.
  attempts,

  /// The elapsed budget was consumed, including queue and retry waits.
  elapsed,

  /// The borrowed rate limiter refused immediate admission.
  rate,

  /// The injected clock moved backwards; automatic work stops conservatively.
  clockRegression,
}

/// Admission control flow, without a fabricated consumer failure.
final class RetryBudgetExceededException implements Exception {
  /// Creates a typed budget rejection.
  const RetryBudgetExceededException(this.reason);

  /// Bound that prevented the attempt.
  final RetryBudgetStop reason;
}

/// Consumer-owned finite budget shared by foreground and background work.
///
/// Create a scope per explicit bootstrap, reconnect, or delivery window. This
/// value borrows its bulkhead and rate limiter and owns no timer or queue.
/// Each admitted leaf attempt consumes one token permanently, including failed
/// attempts. Place retry at one layer; every participating executor must receive
/// this same budget. A budget is isolate-local, not a durable distributed lease.
final class RetryBudget {
  /// Starts an elapsed window immediately, before any admission queueing.
  RetryBudget({
    required this.maxAttempts,
    required this.maxElapsed,
    required this.bulkhead,
    required this.rateLimiter,
    ResilienceClock clock = const SystemResilienceClock(),
  }) : _clock = clock,
       _started = clock.now().toUtc() {
    if (maxAttempts <= 0 || maxElapsed <= Duration.zero) {
      throw ArgumentError('Retry budget bounds must be positive.');
    }
    _lastObserved = _started;
  }

  /// Maximum total leaf attempts across all participating operations.
  final int maxAttempts;

  /// Maximum elapsed time from scope construction to attempt admission.
  final Duration maxElapsed;

  /// Borrowed bounded concurrency and queue authority.
  final Bulkhead bulkhead;

  /// Borrowed immediate token-bucket admission authority.
  final RateLimiter rateLimiter;

  final ResilienceClock _clock;
  final DateTime _started;
  late DateTime _lastObserved;
  var _attempts = 0;
  var _clockRegressed = false;

  /// Total admitted attempts; failed attempts are never refunded.
  int get attemptsStarted => _attempts;

  /// Checks whether a delay leaves time and attempts for later admission.
  ///
  /// Does not reserve concurrency or rate tokens. Admission rechecks all bounds.
  bool canWait(Duration delay) {
    if (delay < Duration.zero) throw ArgumentError.value(delay, 'delay');
    return stopReason == null && delay < maxElapsed - _elapsed;
  }

  Duration get _elapsed => _lastObserved.difference(_started);

  /// Current non-rate stopping reason, observing the clock without queueing.
  RetryBudgetStop? get stopReason {
    final now = _clock.now().toUtc();
    if (now.isBefore(_lastObserved)) _clockRegressed = true;
    if (_clockRegressed) return RetryBudgetStop.clockRegression;
    _lastObserved = now;
    if (_elapsed >= maxElapsed) return RetryBudgetStop.elapsed;
    if (_attempts >= maxAttempts) return RetryBudgetStop.attempts;
    return null;
  }

  /// Consumes one attempt immediately before consumer work, after queueing.
  ///
  /// Callers normally use [RetryExecutor.execute], which performs cancellation
  /// and deadline checks around the borrowed bulkhead admission.
  void startAttempt() {
    final stopped = stopReason;
    if (stopped != null) throw RetryBudgetExceededException(stopped);
    if (!rateLimiter.tryAcquire()) {
      throw const RetryBudgetExceededException(RetryBudgetStop.rate);
    }
    _attempts++;
  }
}
