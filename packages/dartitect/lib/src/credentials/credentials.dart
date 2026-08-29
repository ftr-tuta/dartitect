import 'dart:async';

import '../concurrency/cancellation.dart';
import '../lifecycle/contracts.dart';
import '../result.dart';

/// Immutable credential value with an optional UTC expiry.
final class CredentialRecord<C extends Object> {
  /// Creates a credential record.
  const CredentialRecord({required this.value, this.expiresAt});

  /// Consumer-owned credential value.
  final C value;

  /// Optional absolute UTC expiry.
  final DateTime? expiresAt;

  /// Whether this record is expired at [now], including [skew].
  bool isExpiredAt(DateTime now, {Duration skew = Duration.zero}) =>
      expiresAt != null && !now.toUtc().add(skew).isBefore(expiresAt!);
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

/// Expiry-aware credential owner with refresh single-flight.
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
  Future<Result<CredentialRecord<C>, F>>? _refreshing;
  var _disposed = false;

  /// Loads a valid credential, refreshing through one shared in-flight call.
  Future<Result<CredentialRecord<C>, F>> load({
    CancellationSignal? cancellation,
  }) async {
    _ensureOpen();
    cancellation?.throwIfCancelled();
    _lifetime.signal.throwIfCancelled();
    final read = await store.read(cancellation ?? _lifetime.signal);
    return switch (read) {
      Err<Object>(:final failure, :final stackTrace) => Err<F>(
        failure as F,
        stackTrace,
      ),
      Ok<dynamic>(:final value)
          when value is CredentialRecord<C> &&
              !value.isExpiredAt(_now(), skew: expirySkew) =>
        Ok<CredentialRecord<C>>(value),
      Ok<dynamic>(:final value) => _refreshSingleFlight(
        value as CredentialRecord<C>?,
        cancellation ?? _lifetime.signal,
      ),
    };
  }

  /// Loads credentials for a freshly constructed headless graph.
  Future<Result<CredentialRecord<C>, F>> loadForHeadlessGraph(
    CancellationSignal cancellation,
  ) => load(cancellation: cancellation);

  Future<Result<CredentialRecord<C>, F>> _refreshSingleFlight(
    CredentialRecord<C>? previous,
    CancellationSignal cancellation,
  ) {
    final active = _refreshing;
    if (active != null) return active;
    final future = _refresh(previous, cancellation);
    _refreshing = future;
    void clear() {
      if (identical(_refreshing, future)) _refreshing = null;
    }

    unawaited(future.then<void>((_) => clear(), onError: (_, _) => clear()));
    return future;
  }

  Future<Result<CredentialRecord<C>, F>> _refresh(
    CredentialRecord<C>? previous,
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    _lifetime.signal.throwIfCancelled();
    final refreshed = await refresher.refresh(previous, cancellation);
    switch (refreshed) {
      case Err<Object>(:final failure, :final stackTrace):
        return Err<F>(failure as F, stackTrace);
      case Ok<dynamic>(:final value):
        final credential = value as CredentialRecord<C>;
        cancellation.throwIfCancelled();
        _lifetime.signal.throwIfCancelled();
        final persisted = await store.write(credential, cancellation);
        return switch (persisted) {
          Ok<dynamic>() => Ok<CredentialRecord<C>>(credential),
          Err<Object>(:final failure, :final stackTrace) => Err<F>(
            failure as F,
            stackTrace,
          ),
        };
    }
  }

  /// Clears credentials, then requests forced logout/session rebuild.
  Future<Result<void, F>> invalidate(
    CredentialInvalidationCause cause, {
    CancellationSignal? cancellation,
  }) async {
    _ensureOpen();
    final signal = cancellation ?? _lifetime.signal;
    signal.throwIfCancelled();
    final result = await store.clear(signal);
    if (result case Err<F>()) return result;
    await forcedLogout?.call(cause, signal);
    return result;
  }

  void _ensureOpen() {
    if (_disposed) throw StateError('CredentialsController is disposed.');
  }

  /// Cancels and drains refresh work without owning the consumer store.
  @override
  Future<void> disposeAsync() async {
    if (_disposed) return;
    _disposed = true;
    _lifetime.cancel('CredentialsController disposed');
    await _refreshing?.then<void>((_) {}, onError: (_, _) {});
    _lifetime.dispose();
  }
}
