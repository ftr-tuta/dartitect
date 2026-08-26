import 'package:dartitect/dartitect.dart';
import 'package:flutter/foundation.dart';

/// Stable, non-sensitive reason for a session transition.
enum SessionTransitionCause {
  /// Consumer initiated a normal sign-out.
  signOut,

  /// Authentication expired.
  expired,

  /// Infrastructure required an immediate logout.
  forcedLogout,

  /// A new authenticated session is being installed.
  signIn,
}

/// Replayable application-owned authentication/session state.
sealed class SessionState<S extends Object> extends ValueEquality {
  const SessionState();
}

/// No authenticated generation has been installed yet.
final class SessionAnonymous<S extends Object> extends SessionState<S> {
  /// Creates anonymous state.
  const SessionAnonymous();

  @override
  Iterable<Object?> get equalityFields => const <Object?>[];
}

/// One immutable authenticated session description is active.
final class SessionActive<S extends Object> extends SessionState<S> {
  /// Creates active state for an opaque generation and immutable [value].
  const SessionActive({required this.generation, required this.value});

  /// Opaque graph generation; never a credential or user identifier.
  final Object generation;

  /// Consumer-defined immutable presentation/session description.
  final S value;

  @override
  Iterable<Object?> get equalityFields => <Object?>[generation, value];
}

/// Admission is closing or a new graph is being built.
final class SessionTransitioning<S extends Object> extends SessionState<S> {
  /// Creates a transition state.
  const SessionTransitioning(this.cause);

  /// Sanitized transition cause.
  final SessionTransitionCause cause;

  @override
  Iterable<Object?> get equalityFields => <Object?>[cause];
}

/// The shell must remove authenticated routes while the old graph drains.
final class SessionForcedLogout<S extends Object> extends SessionState<S> {
  /// Creates forced-logout state.
  const SessionForcedLogout({this.expired = false});

  /// Whether expiry, rather than another static policy, caused the logout.
  final bool expired;

  @override
  Iterable<Object?> get equalityFields => <Object?>[expired];
}

/// The previous session graph has fully drained and closed.
final class SessionSignedOut<S extends Object> extends SessionState<S> {
  /// Creates signed-out state.
  const SessionSignedOut();

  @override
  Iterable<Object?> get equalityFields => const <Object?>[];
}

/// Owned replayable state holder used by the application shell/router adapter.
final class SessionStateController<S extends Object>
    extends ValueNotifier<SessionState<S>>
    implements Disposable {
  /// Creates a controller with an explicit initial state.
  SessionStateController(super.value);

  var _disposed = false;

  /// Whether terminal disposal has begun.
  bool get isDisposed => _disposed;

  /// Publishes [next] while the application owner is active.
  void transition(SessionState<S> next) {
    if (_disposed) throw StateError('SessionStateController is disposed.');
    value = next;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
