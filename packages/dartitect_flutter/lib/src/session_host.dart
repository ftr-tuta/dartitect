// This library is the package's explicit Flutter widget boundary.
// ignore_for_file: dartitect_flutter_type_boundary

import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'session_state.dart';

/// Builds the authenticated subtree from the published session runtime.
typedef SessionActiveBuilder<R, D extends Object> = Widget Function(
  BuildContext context,
  R runtime,
  D description,
);

/// Typed, cancellable request to remove routes borrowing an old session graph.
final class SessionRouteRemovalRequest {
  /// Creates a route-removal request owned by the session controller.
  const SessionRouteRemovalRequest({
    required this.transitionId,
    required this.cause,
    required this.deadline,
    required this.cancellation,
  });

  /// Monotonic transition identity.
  final int transitionId;

  /// Static reason for removing the routes.
  final SessionTransitionCause cause;

  /// Absolute UTC deadline for route removal.
  final DateTime deadline;

  /// Cooperative cancellation triggered by timeout or controller disposal.
  final CancellationSignal cancellation;
}

/// Sealed router response for one route-removal request.
sealed class SessionRouteRemovalResult {
  const SessionRouteRemovalResult();
}

/// Successful confirmation that no route borrows the old graph.
final class SessionRouteRemovalSucceeded extends SessionRouteRemovalResult {
  /// Creates a successful confirmation.
  const SessionRouteRemovalSucceeded();
}

/// Typed route-removal failure with its original stack outside UI state.
final class SessionRouteRemovalFailed extends SessionRouteRemovalResult {
  /// Creates a failed confirmation.
  const SessionRouteRemovalFailed({
    required this.error,
    required this.stackTrace,
    this.kind = SessionTransitionFailureKind.routeRemoval,
  });

  /// Original router failure.
  final Object error;

  /// Original router failure stack.
  final StackTrace stackTrace;

  /// Closed presentation-safe category.
  final SessionTransitionFailureKind kind;
}

/// Removes routes that may still borrow the previous runtime generation.
typedef SessionRouteRemover = Future<SessionRouteRemovalResult> Function(
  SessionRouteRemovalRequest request,
);

/// Non-UI failure details retained for the operation caller and retry owner.
final class SessionTransitionFailure {
  /// Creates transition failure details.
  const SessionTransitionFailure({
    required this.transitionId,
    required this.cause,
    required this.kind,
    required this.error,
    required this.stackTrace,
  });

  /// Monotonic transition identity.
  final int transitionId;

  /// Static transition cause.
  final SessionTransitionCause cause;

  /// Closed failure category.
  final SessionTransitionFailureKind kind;

  /// Original failure, never copied into [SessionTransitionFailed].
  final Object error;

  /// Original failure stack, never copied into [SessionTransitionFailed].
  final StackTrace stackTrace;
}

/// Exception returned to the caller when a transition fails before publish.
final class SessionTransitionException implements Exception {
  /// Creates an exception around [failure].
  const SessionTransitionException(this.failure);

  /// Original failure details.
  final SessionTransitionFailure failure;

  @override
  String toString() =>
      'SessionTransitionException(${failure.kind.name}, '
      'transition: ${failure.transitionId})';
}

/// Serial session-runtime owner with cancellable route-removal fencing.
final class SessionRuntimeController<R, D extends Object>
    implements AsyncDisposable {
  /// Creates an anonymous controller.
  SessionRuntimeController({
    this.routeRemovalTimeout = const Duration(seconds: 10),
    DartitectDiagnosticSubject? diagnostics,
  }) : _diagnostics = diagnostics,
       _slot = OwnedRuntimeSlot<R>(
         label: 'SessionRuntimeController',
         diagnostics: diagnostics?.child(DartitectDiagnosticSubjectKind.host),
       ),
       _states = SessionStateController<D>(SessionAnonymous<D>()),
       _stableState = SessionAnonymous<D>() {
    if (routeRemovalTimeout <= Duration.zero) {
      throw ArgumentError.value(
        routeRemovalTimeout,
        'routeRemovalTimeout',
        'Must be positive.',
      );
    }
    if (diagnostics != null &&
        diagnostics.kind != DartitectDiagnosticSubjectKind.host) {
      throw ArgumentError.value(
        diagnostics.kind,
        'diagnostics',
        'SessionRuntimeController requires a host diagnostic subject.',
      );
    }
  }

  /// Default maximum time allowed for route removal.
  final Duration routeRemovalTimeout;

  final DartitectDiagnosticSubject? _diagnostics;
  final OwnedRuntimeSlot<R> _slot;
  final SessionStateController<D> _states;
  Future<void> _tail = Future<void>.value();
  _PendingRouteRemoval? _pendingRemoval;
  _FailedTransition? _failedTransition;
  late SessionState<D> _stableState;
  R? _current;
  D? _currentDescription;
  var _transitionId = 0;
  var _closing = false;
  Future<void>? _disposal;

  /// Replayable state observed by shells and router adapters.
  ValueListenable<SessionState<D>> get states => _states;

  /// Current replayable session state.
  SessionState<D> get state => _states.value;

  /// Monotonic runtime generation.
  int get generation => _slot.generation;

  /// Whether an authenticated runtime is published.
  bool get hasCurrent => _slot.hasCurrent;

  /// Route-removal transition awaiting confirmation, when present.
  int? get pendingRouteRemovalId => _pendingRemoval?.request.transitionId;

  /// Typed pending request exposed to the Flutter/router boundary.
  SessionRouteRemovalRequest? get pendingRouteRemovalRequest =>
      _pendingRemoval?.request;

  /// Latest non-UI failure details, when retry or abort is available.
  SessionTransitionFailure? get failedTransition => _failedTransition?.failure;

  /// Current root for synchronous Flutter composition.
  R get current {
    final value = _current;
    if (!_slot.hasCurrent || value == null) {
      throw StateError('No session runtime is published.');
    }
    return value;
  }

  /// Current immutable session description.
  D get currentDescription {
    final value = _currentDescription;
    if (!_slot.hasCurrent || value == null) {
      throw StateError('No session runtime is published.');
    }
    return value;
  }

  /// Runs [operation] in the generation current at admission time.
  Future<T> use<T>(FutureOr<T> Function(R runtime) operation) =>
      _slot.use(operation);

  /// Builds and atomically publishes a signed-in runtime.
  Future<int> signIn(
    D description,
    FutureOr<R> Function(ResourceTransaction transaction) build,
  ) => replace(description, build, cause: SessionTransitionCause.signIn);

  /// Builds and publishes a replacement after old routes are removed.
  Future<int> replace(
    D description,
    FutureOr<R> Function(ResourceTransaction transaction) build, {
    SessionTransitionCause cause = SessionTransitionCause.tenantSwitch,
  }) {
    _ensureOpen();
    final retry = () async {
      await replace(description, build, cause: cause);
    };
    return _enqueue<int>(() async {
      _beginAttempt();
      final transitionId = ++_transitionId;
      OwnedGraph<R>? next;
      var handedToSlot = false;
      try {
        next = await ResourceTransaction.create<R>(
          build,
          label: 'SessionRuntimeController.transaction',
        );
        if (_closing) {
          throw const CancellationException(
            'SessionRuntimeController disposed',
          );
        }
        if (_slot.hasCurrent) {
          _diagnostics?.emit(
            DartitectDiagnosticPhase.waiting,
            generation: _slot.generation,
          );
          await _waitForRouteRemoval(
            transitionId,
            cause,
            SessionTransitioning<D>(cause),
          );
        }
        if (_closing) {
          throw const CancellationException(
            'SessionRuntimeController disposed',
          );
        }
        handedToSlot = true;
        final generation = await _slot.replaceGraph(() => next!);
        _current = next.root;
        _currentDescription = description;
        _setStable(
          SessionActive<D>(generation: generation, value: description),
        );
        _diagnostics?.emit(
          DartitectDiagnosticPhase.updated,
          generation: generation,
        );
        return generation;
      } on OwnedRuntimeReplacementCleanupException catch (error) {
        _current = next!.root;
        _currentDescription = description;
        _setStable(
          SessionActive<D>(
            generation: error.publishedGeneration,
            value: description,
          ),
        );
        rethrow;
      } catch (error, stackTrace) {
        if (!handedToSlot && next != null) {
          try {
            await next.disposeAsync();
          } catch (cleanupError, cleanupStackTrace) {
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: cleanupError,
                stack: cleanupStackTrace,
                library: 'dartitect_flutter',
                context: ErrorDescription(
                  'while disposing a rejected session graph',
                ),
              ),
            );
          }
        }
        final failure = error is SessionTransitionException
            ? error.failure
            : SessionTransitionFailure(
                transitionId: transitionId,
                cause: cause,
                kind: _closing
                    ? SessionTransitionFailureKind.disposed
                    : error is CancellationException
                    ? SessionTransitionFailureKind.cancelled
                    : SessionTransitionFailureKind.graphPreparation,
                error: error,
                stackTrace: stackTrace,
              );
        _recordFailure(failure, retry);
        Error.throwWithStackTrace(
          error is SessionTransitionException
              ? error
              : SessionTransitionException(failure),
          failure.stackTrace,
        );
      }
    });
  }

  /// Signs out after explicit removal of routes borrowing the old runtime.
  Future<void> signOut() => _remove(SessionTransitionCause.signOut);

  /// Forces logout or expiry after explicit route-removal confirmation.
  Future<void> forceLogout({bool expired = false}) => _remove(
    expired
        ? SessionTransitionCause.expired
        : SessionTransitionCause.forcedLogout,
    forced: true,
    expired: expired,
  );

  Future<void> _remove(
    SessionTransitionCause cause, {
    bool forced = false,
    bool expired = false,
  }) {
    _ensureOpen();
    final retry = () => _remove(cause, forced: forced, expired: expired);
    return _enqueue<void>(() async {
      _beginAttempt();
      final transitionId = ++_transitionId;
      try {
        if (!_slot.hasCurrent) {
          _current = null;
          _currentDescription = null;
          _setStable(SessionSignedOut<D>());
          return;
        }
        await _waitForRouteRemoval(
          transitionId,
          cause,
          forced
              ? SessionForcedLogout<D>(expired: expired)
              : SessionTransitioning<D>(cause),
        );
        await _slot.clearCurrent();
        _current = null;
        _currentDescription = null;
        _setStable(SessionSignedOut<D>());
        _diagnostics?.emit(
          DartitectDiagnosticPhase.updated,
          generation: _slot.generation,
        );
      } catch (error, stackTrace) {
        final failure = error is SessionTransitionException
            ? error.failure
            : SessionTransitionFailure(
                transitionId: transitionId,
                cause: cause,
                kind: _closing
                    ? SessionTransitionFailureKind.disposed
                    : error is CancellationException
                    ? SessionTransitionFailureKind.cancelled
                    : SessionTransitionFailureKind.routeRemoval,
                error: error,
                stackTrace: stackTrace,
              );
        _recordFailure(failure, retry);
        Error.throwWithStackTrace(
          error is SessionTransitionException
              ? error
              : SessionTransitionException(failure),
          failure.stackTrace,
        );
      }
    });
  }

  Future<void> _waitForRouteRemoval(
    int transitionId,
    SessionTransitionCause cause,
    SessionState<D> transition,
  ) async {
    final source = CancellationSource();
    final completer = Completer<SessionRouteRemovalResult>();
    final deadline = DateTime.now().toUtc().add(routeRemovalTimeout);
    late final _PendingRouteRemoval pending;
    final timer = Timer(routeRemovalTimeout, () {
      final error = TimeoutException(
        'Session route removal exceeded its deadline.',
        routeRemovalTimeout,
      );
      _completePending(
        pending,
        SessionRouteRemovalFailed(
          error: error,
          stackTrace: StackTrace.current,
          kind: SessionTransitionFailureKind.deadlineExceeded,
        ),
        cancelReason: 'Session route-removal deadline exceeded',
      );
    });
    pending = _PendingRouteRemoval(
      request: SessionRouteRemovalRequest(
        transitionId: transitionId,
        cause: cause,
        deadline: deadline,
        cancellation: source.signal,
      ),
      source: source,
      completer: completer,
      timer: timer,
    );
    _pendingRemoval = pending;
    _states.transition(transition);
    final result = await completer.future;
    if (result case SessionRouteRemovalFailed(
      :final error,
      :final stackTrace,
      :final kind,
    )) {
      final failure = SessionTransitionFailure(
        transitionId: transitionId,
        cause: cause,
        kind: kind,
        error: error,
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(
        SessionTransitionException(failure),
        stackTrace,
      );
    }
  }

  /// Completes the pending route-removal fence with a typed router result.
  bool completeRouteRemoval(
    int transitionId,
    SessionRouteRemovalResult result,
  ) {
    final pending = _pendingRemoval;
    if (pending == null ||
        pending.request.transitionId != transitionId ||
        pending.completer.isCompleted) {
      return false;
    }
    _completePending(
      pending,
      result,
      cancelReason: result is SessionRouteRemovalFailed
          ? 'Session route removal failed'
          : null,
    );
    return true;
  }

  void _completePending(
    _PendingRouteRemoval pending,
    SessionRouteRemovalResult result, {
    required Object? cancelReason,
  }) {
    if (!identical(_pendingRemoval, pending) || pending.completer.isCompleted) {
      return;
    }
    _pendingRemoval = null;
    pending.timer.cancel();
    if (cancelReason != null) pending.source.cancel(cancelReason);
    pending.completer.complete(result);
    pending.source.dispose();
  }

  /// Restores the last stable state and discards the stored retry operation.
  bool abortFailedTransition() {
    if (_closing || _failedTransition == null) return false;
    _failedTransition = null;
    _states.transition(_stableState);
    return true;
  }

  /// Retries the exact operation that produced [failedTransition].
  Future<void> retryFailedTransition() {
    _ensureOpen();
    final failed = _failedTransition;
    if (failed == null) {
      throw StateError('No failed session transition is available.');
    }
    _failedTransition = null;
    _states.transition(_stableState);
    return failed.retry();
  }

  void _beginAttempt() {
    if (_failedTransition == null) return;
    _failedTransition = null;
    _states.transition(_stableState);
  }

  void _recordFailure(
    SessionTransitionFailure failure,
    Future<void> Function() retry,
  ) {
    if (_closing) return;
    _failedTransition = _FailedTransition(failure: failure, retry: retry);
    _states.transition(
      SessionTransitionFailed<D>(
        transitionId: failure.transitionId,
        cause: failure.cause,
        kind: failure.kind,
      ),
    );
    _diagnostics?.emit(
      DartitectDiagnosticPhase.failed,
      generation: _slot.generation,
    );
  }

  void _setStable(SessionState<D> state) {
    _stableState = state;
    _failedTransition = null;
    _states.transition(state);
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail
        .then((_) async {
          _ensureOpen();
          try {
            completer.complete(await operation());
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!completer.isCompleted)
            completer.completeError(error, stackTrace);
        });
    return completer.future;
  }

  void _ensureOpen() {
    if (_closing) throw StateError('SessionRuntimeController is disposed.');
  }

  /// Stops transitions, cancels pending route work, and drains the graph.
  @override
  Future<void> disposeAsync() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    if (_closing) return;
    _closing = true;
    final pending = _pendingRemoval;
    if (pending != null) {
      final cancellation = const CancellationException(
        'SessionRuntimeController disposed',
      );
      _completePending(
        pending,
        SessionRouteRemovalFailed(
          error: cancellation,
          stackTrace: StackTrace.current,
          kind: SessionTransitionFailureKind.disposed,
        ),
        cancelReason: 'SessionRuntimeController disposed',
      );
    }
    await _tail;
    await _slot.disposeAsync();
    _current = null;
    _currentDescription = null;
    _failedTransition = null;
    _states.dispose();
    _diagnostics?.emit(
      DartitectDiagnosticPhase.disposed,
      generation: _slot.generation,
    );
  }
}

final class _PendingRouteRemoval {
  const _PendingRouteRemoval({
    required this.request,
    required this.source,
    required this.completer,
    required this.timer,
  });

  final SessionRouteRemovalRequest request;
  final CancellationSource source;
  final Completer<SessionRouteRemovalResult> completer;
  final Timer timer;
}

final class _FailedTransition {
  const _FailedTransition({required this.failure, required this.retry});

  final SessionTransitionFailure failure;
  final Future<void> Function() retry;
}

/// Flutter shell for an owned or borrowed [SessionRuntimeController].
final class SessionHost<R, D extends Object> extends StatefulWidget {
  /// Creates and owns one controller.
  const SessionHost.create({
    required SessionRuntimeController<R, D> Function() create,
    required this.removeRoutes,
    required this.anonymous,
    required this.transitioning,
    required this.active,
    super.key,
  }) : _create = create,
       _value = null,
       _ownsController = true;

  /// Borrows [value] and never disposes it.
  const SessionHost.value({
    required SessionRuntimeController<R, D> value,
    required this.removeRoutes,
    required this.anonymous,
    required this.transitioning,
    required this.active,
    super.key,
  }) : _value = value,
       _create = null,
       _ownsController = false;

  final SessionRuntimeController<R, D> Function()? _create;
  final SessionRuntimeController<R, D>? _value;
  final bool _ownsController;

  /// Router boundary that returns only after old routes are gone or failed.
  final SessionRouteRemover removeRoutes;

  /// Anonymous and fully signed-out subtree.
  final WidgetBuilder anonymous;

  /// Transition/failure subtree, which must not borrow the old runtime.
  final Widget Function(BuildContext context, SessionState<D> state)
  transitioning;

  /// Authenticated subtree.
  final SessionActiveBuilder<R, D> active;

  @override
  State<SessionHost<R, D>> createState() => _SessionHostState<R, D>();
}

final class _SessionHostState<R, D extends Object>
    extends State<SessionHost<R, D>> {
  late SessionRuntimeController<R, D> _controller;
  late bool _ownsController;
  int? _removingId;

  @override
  void initState() {
    super.initState();
    _adopt();
  }

  @override
  void didUpdateWidget(covariant SessionHost<R, D> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._ownsController && widget._ownsController) return;
    if (!oldWidget._ownsController &&
        !widget._ownsController &&
        identical(oldWidget._value, widget._value)) {
      return;
    }
    _controller.states.removeListener(_changed);
    if (_ownsController) _watch(_controller.disposeAsync());
    _adopt();
  }

  void _adopt() {
    _ownsController = widget._ownsController;
    _controller = _ownsController ? widget._create!() : widget._value!;
    _controller.states.addListener(_changed);
    _requestRemovalIfNeeded();
  }

  void _changed() {
    if (mounted) setState(() {});
    _requestRemovalIfNeeded();
  }

  void _requestRemovalIfNeeded() {
    final request = _controller.pendingRouteRemovalRequest;
    if (request == null || request.transitionId == _removingId) return;
    final id = request.transitionId;
    _removingId = id;
    unawaited(
      _removeRoutes(request).then<void>((result) {
        _controller.completeRouteRemoval(id, result);
        if (_removingId == id) _removingId = null;
      }),
    );
  }

  Future<SessionRouteRemovalResult> _removeRoutes(
    SessionRouteRemovalRequest request,
  ) async {
    try {
      return await widget.removeRoutes(request);
    } catch (error, stackTrace) {
      return SessionRouteRemovalFailed(error: error, stackTrace: stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    return switch (state) {
      SessionAnonymous<D>() ||
      SessionSignedOut<D>() => widget.anonymous(context),
      SessionActive<D>(:final value) => widget.active(
        context,
        _controller.current,
        value,
      ),
      SessionTransitioning<D>() ||
      SessionForcedLogout<D>() ||
      SessionTransitionFailed<D>() => widget.transitioning(context, state),
    };
  }

  @override
  void dispose() {
    _controller.states.removeListener(_changed);
    if (_ownsController) _watch(_controller.disposeAsync());
    super.dispose();
  }

  void _watch(Future<void> future) {
    unawaited(future.catchError(_report));
  }

  void _report(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'dartitect_flutter',
        context: ErrorDescription('while operating a SessionHost'),
      ),
    );
  }
}
