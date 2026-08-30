import 'dart:async';

import '../concurrency/cancellation.dart';
import '../lifecycle/contracts.dart';
import '../result.dart';

/// Immutable credential value with an optional UTC expiry.
final class CredentialRecord<C extends Object> {
  /// Creates a credential record.
  CredentialRecord({required this.value, this.expiresAt}) {
    if (expiresAt != null && !expiresAt!.isUtc) {
      throw ArgumentError.value(expiresAt, 'expiresAt', 'Must use UTC.');
    }
  }

  /// Consumer-owned credential value.
  final C value;

  /// Optional absolute UTC expiry.
  final DateTime? expiresAt;

  /// Whether this record is expired at [now], including [skew].
  bool isExpiredAt(DateTime now, {Duration skew = Duration.zero}) {
    if (skew.isNegative) {
      throw ArgumentError.value(skew, 'skew', 'Must be non-negative.');
    }
    return expiresAt != null && !now.toUtc().add(skew).isBefore(expiresAt!);
  }
}

/// Opaque identity for one credential publication generation.
final class CredentialGeneration {
  const CredentialGeneration._(this.value);

  /// Monotonic process-local value used only for diagnostics.
  final int value;

  @override
  String toString() => 'CredentialGeneration($value)';
}

/// A credential record fenced to the generation that published it.
final class CredentialLease<C extends Object> {
  const CredentialLease._({required this.credential, required this.generation});

  /// Credential published for this generation.
  final CredentialRecord<C> credential;

  /// Identity that must accompany work using [credential].
  final CredentialGeneration generation;

  /// Convenience access to the consumer-owned credential value.
  C get value => credential.value;

  /// Convenience access to the optional UTC expiry.
  DateTime? get expiresAt => credential.expiresAt;
}

/// Consumer-owned durable credential store.
abstract interface class CredentialStore<C extends Object, F extends Object> {
  /// Reads the current credential, or `null` when signed out.
  Future<Result<CredentialRecord<C>?, F>> read(CancellationSignal cancellation);

  /// Persists a refreshed credential before it is published.
  Future<Result<void, F>> write(
    CredentialRecord<C> credential,
    CancellationSignal cancellation,
  );

  /// Invalidates persisted credentials.
  Future<Result<void, F>> clear(CancellationSignal cancellation);
}

/// Consumer-owned credential refresh boundary.
abstract interface class CredentialRefresher<
  C extends Object,
  F extends Object
> {
  /// Refreshes an expired or absent credential.
  Future<Result<CredentialRecord<C>, F>> refresh(
    CredentialRecord<C>? previous,
    CancellationSignal cancellation,
  );
}

/// Why credentials were invalidated.
enum CredentialInvalidationCause {
  /// Explicit application sign-out.
  signOut,

  /// Credential refresh was rejected.
  refreshRejected,

  /// Provider reported that authentication is no longer valid.
  providerRejected,
}

/// Consumer callback that forces logout and rebuilds the session graph.
typedef CredentialForcedLogout = FutureOr<void> Function(
  CredentialInvalidationCause cause,
  CancellationSignal cancellation,
);

/// Expiry-aware credential owner with generation-fenced single-flight.
final class CredentialsController<C extends Object, F extends Object>
    implements AsyncDisposable {
  /// Creates a controller over consumer-owned [store] and [refresher].
  CredentialsController({
    required this.store,
    required this.refresher,
    required DateTime Function() now,
    this.expirySkew = const Duration(seconds: 30),
    this.forcedLogout,
  }) : _now = now {
    if (expirySkew.isNegative) {
      throw ArgumentError.value(
        expirySkew,
        'expirySkew',
        'Must be non-negative.',
      );
    }
  }

  /// Consumer-owned storage port.
  final CredentialStore<C, F> store;

  /// Consumer-owned refresh port.
  final CredentialRefresher<C, F> refresher;

  /// Early-refresh allowance.
  final Duration expirySkew;

  /// Optional session invalidation and rebuild callback.
  final CredentialForcedLogout? forcedLogout;

  final DateTime Function() _now;
  final CancellationSource _lifetime = CancellationSource();
  Future<Result<CredentialLease<C>, F>>? _acquiring;
  CancellationSource? _acquisitionCancellation;
  CredentialLease<C>? _current;
  Future<Result<void, F>>? _invalidating;
  CredentialGeneration? _invalidatingGeneration;
  var _revision = 0;
  var _nextGeneration = 0;
  var _hasActiveGeneration = true;
  var _disposed = false;

  /// Current published lease, or `null` before load and after invalidation.
  CredentialLease<C>? get currentLease => _current;

  /// Loads a valid credential lease through one shared acquisition.
  ///
  /// Each caller observes its own [cancellation]. Cancelling one waiter never
  /// cancels the shared store read, refresh, or persistence used by others.
  Future<Result<CredentialLease<C>, F>> load({
    CancellationSignal? cancellation,
  }) {
    _ensureOpen();
    cancellation?.throwIfCancelled();
    _lifetime.signal.throwIfCancelled();
    final current = _current;
    if (current != null &&
        !current.credential.isExpiredAt(_now(), skew: expirySkew)) {
      return _waitFor(
        Future<Result<CredentialLease<C>, F>>.value(
          Ok<CredentialLease<C>>(current),
        ),
        cancellation,
      );
    }
    final active = _acquiring ?? _startAcquisition(current?.credential);
    return _waitFor(active, cancellation);
  }

  /// Loads credentials for a freshly constructed headless graph.
  Future<Result<CredentialLease<C>, F>> loadForHeadlessGraph(
    CancellationSignal cancellation,
  ) => load(cancellation: cancellation);

  Future<Result<CredentialLease<C>, F>> _startAcquisition(
    CredentialRecord<C>? previous,
  ) {
    final expectedRevision = _revision;
    final source = CancellationSource();
    _acquisitionCancellation = source;
    final future = _acquire(previous, expectedRevision, source.signal);
    _acquiring = future;
    void clear() {
      if (identical(_acquiring, future)) {
        _acquiring = null;
        _acquisitionCancellation = null;
      }
      source.dispose();
    }

    unawaited(future.then<void>((_) => clear(), onError: (_, _) => clear()));
    return future;
  }

  Future<Result<CredentialLease<C>, F>> _acquire(
    CredentialRecord<C>? previous,
    int expectedRevision,
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    _lifetime.signal.throwIfCancelled();
    var candidate = previous;
    if (candidate == null) {
      final read = await store.read(cancellation);
      switch (read) {
        case Err<Object>(:final failure, :final stackTrace):
          return Err<F>(failure as F, stackTrace);
        case Ok<dynamic>(:final value):
          candidate = value as CredentialRecord<C>?;
      }
      _ensureRevision(expectedRevision, cancellation);
    }
    if (candidate != null && !candidate.isExpiredAt(_now(), skew: expirySkew)) {
      return Ok<CredentialLease<C>>(
        _publish(candidate, expectedRevision, cancellation),
      );
    }

    final refreshed = await refresher.refresh(candidate, cancellation);
    switch (refreshed) {
      case Err<Object>(:final failure, :final stackTrace):
        return Err<F>(failure as F, stackTrace);
      case Ok<dynamic>(:final value):
        final credential = value as CredentialRecord<C>;
        _ensureRevision(expectedRevision, cancellation);
        final persisted = await store.write(credential, cancellation);
        _ensureRevision(expectedRevision, cancellation);
        return switch (persisted) {
          Ok<dynamic>() => Ok<CredentialLease<C>>(
            _publish(credential, expectedRevision, cancellation),
          ),
          Err<Object>(:final failure, :final stackTrace) => Err<F>(
            failure as F,
            stackTrace,
          ),
        };
    }
  }

  CredentialLease<C> _publish(
    CredentialRecord<C> credential,
    int expectedRevision,
    CancellationSignal cancellation,
  ) {
    _ensureRevision(expectedRevision, cancellation);
    final lease = CredentialLease<C>._(
      credential: credential,
      generation: CredentialGeneration._(++_nextGeneration),
    );
    _current = lease;
    _hasActiveGeneration = true;
    _revision += 1;
    return lease;
  }

  void _ensureRevision(int expectedRevision, CancellationSignal cancellation) {
    cancellation.throwIfCancelled();
    _lifetime.signal.throwIfCancelled();
    if (_revision != expectedRevision) {
      throw const CancellationException(
        'Credential generation is no longer current',
      );
    }
  }

  /// Clears the active generation, then requests one forced session logout.
  Future<Result<void, F>> invalidate(
    CredentialInvalidationCause cause, {
    CancellationSignal? cancellation,
  }) {
    _ensureOpen();
    cancellation?.throwIfCancelled();
    final active = _invalidating;
    if (active != null) return _waitFor(active, cancellation);
    if (!_hasActiveGeneration) {
      return _waitFor(
        Future<Result<void, F>>.value(const Ok<void>(null)),
        cancellation,
      );
    }
    return _invalidateCurrent(cause, cancellation: cancellation);
  }

  /// Invalidates only when [generation] is still authoritative.
  Future<Result<void, F>> invalidateIfCurrent(
    CredentialGeneration generation,
    CredentialInvalidationCause cause, {
    CancellationSignal? cancellation,
  }) {
    _ensureOpen();
    cancellation?.throwIfCancelled();
    if (_invalidatingGeneration == generation && _invalidating != null) {
      return _waitFor(_invalidating!, cancellation);
    }
    if (_current?.generation != generation) {
      return _waitFor(
        Future<Result<void, F>>.value(const Ok<void>(null)),
        cancellation,
      );
    }
    return _invalidateCurrent(
      cause,
      generation: generation,
      cancellation: cancellation,
    );
  }

  Future<Result<void, F>> _invalidateCurrent(
    CredentialInvalidationCause cause, {
    CredentialGeneration? generation,
    CancellationSignal? cancellation,
  }) {
    final invalidatedGeneration = generation ?? _current?.generation;
    _revision += 1;
    _current = null;
    _hasActiveGeneration = false;
    _invalidatingGeneration = invalidatedGeneration;
    final acquisition = _acquiring;
    _acquisitionCancellation?.cancel('Credential generation invalidated');
    final future = _clearAfterDrain(acquisition, cause);
    _invalidating = future;
    void clear() {
      if (identical(_invalidating, future)) {
        _invalidating = null;
        _invalidatingGeneration = null;
      }
    }

    unawaited(future.then<void>((_) => clear(), onError: (_, _) => clear()));
    return _waitFor(future, cancellation);
  }

  Future<Result<void, F>> _clearAfterDrain(
    Future<Result<CredentialLease<C>, F>>? acquisition,
    CredentialInvalidationCause cause,
  ) async {
    await acquisition?.then<void>((_) {}, onError: (_, _) {});
    _lifetime.signal.throwIfCancelled();
    final result = await store.clear(_lifetime.signal);
    if (result case Err<F>()) return result;
    await forcedLogout?.call(cause, _lifetime.signal);
    return result;
  }

  Future<T> _waitFor<T>(Future<T> operation, CancellationSignal? waiter) {
    if (waiter == null) return operation;
    waiter.throwIfCancelled();
    final completer = Completer<T>();
    final registration = waiter.register((reason) {
      if (!completer.isCompleted) {
        completer.completeError(CancellationException(reason));
      }
    });
    unawaited(
      operation.then<void>(
        (value) {
          if (!completer.isCompleted) completer.complete(value);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        },
      ),
    );
    return completer.future.whenComplete(registration.dispose);
  }

  void _ensureOpen() {
    if (_disposed) throw StateError('CredentialsController is disposed.');
  }

  /// Invalidates the generation, cancels and drains owned work, and never
  /// disposes the consumer-owned store or refresher.
  @override
  Future<void> disposeAsync() async {
    if (_disposed) return;
    _disposed = true;
    _revision += 1;
    _current = null;
    _hasActiveGeneration = false;
    _acquisitionCancellation?.cancel('CredentialsController disposed');
    _lifetime.cancel('CredentialsController disposed');
    await _acquiring?.then<void>((_) {}, onError: (_, _) {});
    await _invalidating?.then<void>((_) {}, onError: (_, _) {});
    _lifetime.dispose();
  }
}
