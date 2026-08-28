import 'dart:async';
import 'dart:math';

import 'package:dartitect/dartitect.dart';

/// Clock injected into resilience policies.
abstract interface class ResilienceClock {
  /// Current UTC time.
  DateTime now();
}

/// System UTC clock.
final class SystemResilienceClock implements ResilienceClock {
  /// Creates the system clock.
  const SystemResilienceClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

/// Scheduler injected into retry and queue policies.
abstract interface class ResilienceScheduler {
  /// Waits for [delay] or throws cooperative cancellation.
  Future<void> wait(Duration delay, CancellationSignal cancellation);
}

/// Timer-backed scheduler with explicit cancellation cleanup.
final class TimerResilienceScheduler implements ResilienceScheduler {
  /// Creates a timer-backed scheduler.
  const TimerResilienceScheduler();

  @override
  Future<void> wait(Duration delay, CancellationSignal cancellation) {
    cancellation.throwIfCancelled();
    if (delay <= Duration.zero) return Future<void>.value();
    final completer = Completer<void>();
    late final Timer timer;
    late final CancellationRegistration registration;
    timer = Timer(delay, () {
      registration.dispose();
      if (!completer.isCompleted) completer.complete();
    });
    registration = cancellation.register((reason) {
      timer.cancel();
      if (!completer.isCompleted) {
        completer.completeError(CancellationException(reason));
      }
    });
    return completer.future;
  }
}

/// Randomness injected into jitter strategies.
abstract interface class ResilienceRandom {
  /// A value in the half-open range from zero to one.
  double nextDouble();
}

/// Secure system randomness for retry jitter.
final class SystemResilienceRandom implements ResilienceRandom {
  /// Creates a secure random source.
  SystemResilienceRandom() : _random = Random.secure();

  final Random _random;

  @override
  double nextDouble() => _random.nextDouble();
}

/// Delay calculation before a retry after [failedAttempt].
abstract interface class BackoffStrategy {
  /// Returns a non-negative bounded delay.
  Duration delayAfter(int failedAttempt);
}

/// Constant retry delay.
final class FixedBackoff implements BackoffStrategy {
  /// Creates a fixed non-negative [delay].
  FixedBackoff(this.delay) {
    if (delay < Duration.zero) {
      throw ArgumentError.value(delay, 'delay', 'Must not be negative.');
    }
  }

  /// Delay used after every failed attempt.
  final Duration delay;

  @override
  Duration delayAfter(int failedAttempt) {
    _requireFailedAttempt(failedAttempt);
    return delay;
  }
}

/// Exponential backoff capped at [maximum].
final class ExponentialBackoff implements BackoffStrategy {
  /// Creates a bounded exponential strategy.
  ExponentialBackoff({
    this.initial = const Duration(milliseconds: 200),
    this.multiplier = 2,
    this.maximum = const Duration(seconds: 30),
  }) {
    if (initial <= Duration.zero || multiplier < 1 || maximum < initial) {
      throw ArgumentError('Backoff bounds are invalid.');
    }
  }

  /// Delay after the first failed attempt.
  final Duration initial;

  /// Integer multiplier applied per subsequent failure.
  final int multiplier;

  /// Maximum delay returned.
  final Duration maximum;

  @override
  Duration delayAfter(int failedAttempt) {
    _requireFailedAttempt(failedAttempt);
    var microseconds = initial.inMicroseconds;
    for (var index = 1; index < failedAttempt; index += 1) {
      microseconds *= multiplier;
      if (microseconds >= maximum.inMicroseconds) return maximum;
    }
    return Duration(
      microseconds: microseconds.clamp(0, maximum.inMicroseconds),
    );
  }
}

/// Randomization applied to one backoff delay.
abstract interface class JitterStrategy {
  /// Returns a delay no greater than the policy's documented bound.
  Duration apply(Duration delay, ResilienceRandom random);
}

/// Leaves backoff unchanged.
final class NoJitter implements JitterStrategy {
  /// Creates the deterministic strategy.
  const NoJitter();

  @override
  Duration apply(Duration delay, ResilienceRandom random) => delay;
}

/// Selects uniformly between zero and the complete backoff delay.
final class FullJitter implements JitterStrategy {
  /// Creates full jitter.
  const FullJitter();

  @override
  Duration apply(Duration delay, ResilienceRandom random) {
    if (delay <= Duration.zero) return Duration.zero;
    final value = random.nextDouble();
    if (value < 0 || value >= 1) {
      throw StateError('ResilienceRandom must return a value in [0, 1).');
    }
    return Duration(microseconds: (delay.inMicroseconds * value).floor());
  }
}

/// Expected-failure retry disposition.
enum RetryDecisionKind {
  /// Return the expected failure without another attempt.
  stop,

  /// Retry within every configured bound.
  retry,

  /// Delivery may have committed and must never retry automatically.
  uncertain,
}

/// Closed decision produced only for an expected typed failure.
final class RetryDecision {
  /// Stops without another attempt.
  const RetryDecision.stop() : kind = RetryDecisionKind.stop;

  /// Allows another bounded attempt.
  const RetryDecision.retry() : kind = RetryDecisionKind.retry;

  /// Records an uncertain outcome that forbids automatic retry.
  const RetryDecision.uncertain() : kind = RetryDecisionKind.uncertain;

  /// Decision category.
  final RetryDecisionKind kind;
}

/// Attempt, elapsed-time, backoff, jitter, and failure classification policy.
final class RetryPolicy<F extends Object> {
  /// Creates an explicit bounded policy.
  RetryPolicy({
    required RetryDecision Function(F failure) classify,
    this.maxAttempts = 3,
    this.maxElapsed = const Duration(seconds: 30),
    BackoffStrategy? backoff,
    JitterStrategy jitter = const NoJitter(),
  }) : _classify = classify,
       backoff = backoff ?? ExponentialBackoff(),
       jitter = jitter {
    if (maxAttempts <= 0 || maxElapsed <= Duration.zero) {
      throw ArgumentError(
        'Retry attempts and elapsed budget must be positive.',
      );
    }
  }

  /// Total attempts including the first.
  final int maxAttempts;

  /// Maximum wall-clock budget observed through the injected clock.
  final Duration maxElapsed;

  /// Delay strategy before each retry.
  final BackoffStrategy backoff;

  /// Randomization strategy applied after backoff.
  final JitterStrategy jitter;

  final RetryDecision Function(F failure) _classify;

  /// Classifies one expected typed [failure].
  RetryDecision classify(F failure) => _classify(failure);
}

/// Executes expected-failure retries without catching unexpected crashes.
final class RetryExecutor {
  /// Creates an executor with injectable time and randomness.
  RetryExecutor({
    ResilienceClock clock = const SystemResilienceClock(),
    ResilienceScheduler scheduler = const TimerResilienceScheduler(),
    ResilienceRandom? random,
  }) : _clock = clock,
       _scheduler = scheduler,
       _random = random ?? SystemResilienceRandom();

  final ResilienceClock _clock;
  final ResilienceScheduler _scheduler;
  final ResilienceRandom _random;

  /// Runs [operation] until success or one explicit bound stops retry.
  ///
  /// Unexpected exceptions, cancellation, and deadline exceptions are not
  /// converted to [Result].
  Future<Result<T, F>> execute<T, F extends Object>({
    required Future<Result<T, F>> Function(
      int attempt,
      CancellationSignal cancellation,
    )
    operation,
    required RetryPolicy<F> policy,
    required CancellationSignal cancellation,
    DateTime? deadline,
  }) async {
    if (deadline != null && !deadline.isUtc) {
      throw ArgumentError.value(deadline, 'deadline', 'Must use UTC.');
    }
    final started = _clock.now().toUtc();
    for (var attempt = 1; ; attempt += 1) {
      cancellation.throwIfCancelled();
      _throwIfDeadline(deadline);
      final result = await operation(attempt, cancellation);
      if (result case Ok<dynamic>()) return result;
      final failure = (result as Err<Object>).failure as F;
      final decision = policy.classify(failure);
      if (decision.kind != RetryDecisionKind.retry ||
          attempt >= policy.maxAttempts) {
        return result;
      }
      final delay = policy.jitter.apply(
        policy.backoff.delayAfter(attempt),
        _random,
      );
      final now = _clock.now().toUtc();
      if (now.difference(started) + delay > policy.maxElapsed ||
          deadline != null && !now.add(delay).isBefore(deadline)) {
        return result;
      }
      await _scheduler.wait(delay, cancellation);
    }
  }

  void _throwIfDeadline(DateTime? deadline) {
    if (deadline != null && !_clock.now().toUtc().isBefore(deadline)) {
      throw OperationDeadlineExceededException(deadline);
    }
  }
}

void _requireFailedAttempt(int attempt) {
  if (attempt <= 0) {
    throw ArgumentError.value(attempt, 'failedAttempt', 'Must be positive.');
  }
}
