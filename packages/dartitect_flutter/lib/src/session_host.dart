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

/// Removes routes that may still borrow the previous runtime generation.
typedef SessionRouteRemover = Future<void> Function(int transitionId);

/// Serial session-runtime owner with route-removal fencing.
final class SessionRuntimeController<R, D extends Object>
    implements AsyncDisposable {
  /// Creates an anonymous controller.
  SessionRuntimeController({DartitectDiagnosticSubject? diagnostics})
    : _diagnostics = diagnostics,
      _slot = OwnedRuntimeSlot<R>(
        label: 'SessionRuntimeController',
        diagnostics: diagnostics?.child(DartitectDiagnosticSubjectKind.host),
      ),
      _states = SessionStateController<D>(SessionAnonymous<D>()) {
    if (diagnostics != null &&
        diagnostics.kind != DartitectDiagnosticSubjectKind.host) {
      throw ArgumentError.value(
        diagnostics.kind,
        'diagnostics',
        'SessionRuntimeController requires a host diagnostic subject.',
      );
    }
  }

  final DartitectDiagnosticSubject? _diagnostics;
  final OwnedRuntimeSlot<R> _slot;
  final SessionStateController<D> _states;
  Future<void> _tail = Future<void>.value();
  Completer<void>? _routeRemoval;
  int? _routeRemovalId;
  R? _current;
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
  int? get pendingRouteRemovalId => _routeRemovalId;

  /// Current root for synchronous Flutter composition.
  R get current {
    final value = _current;
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
    final completer = Completer<int>();
    _tail = _tail
        .then((_) async {
          _ensureOpen();
          final next = await ResourceTransaction.create<R>(
            build,
            label: 'SessionRuntimeController.transaction',
          );
          if (_closing) {
            await next.disposeAsync();
            throw StateError('SessionRuntimeController is shutting down.');
          }
          if (_slot.hasCurrent) {
            _diagnostics?.emit(
              DartitectDiagnosticPhase.waiting,
              generation: _slot.generation,
            );
            await _waitForRouteRemoval(SessionTransitioning<D>(cause));
          }
          if (_closing) {
            await next.disposeAsync();
            throw StateError('SessionRuntimeController is shutting down.');
          }
          try {
            final generation = await _slot.replaceGraph(() => next);
            _current = next.root;
            _states.transition(
              SessionActive<D>(generation: generation, value: description),
            );
            _diagnostics?.emit(
              DartitectDiagnosticPhase.updated,
              generation: generation,
            );
            completer.complete(generation);
          } on OwnedRuntimeReplacementCleanupException catch (error) {
            _current = next.root;
            _states.transition(
              SessionActive<D>(
                generation: error.publishedGeneration,
                value: description,
              ),
            );
            rethrow;
          }
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        });
    return completer.future;
  }

  /// Signs out after explicit removal of routes borrowing the old runtime.
  Future<void> signOut() =>
      _remove(SessionTransitioning<D>(SessionTransitionCause.signOut));

  /// Forces logout or expiry after explicit route-removal confirmation.
  Future<void> forceLogout({bool expired = false}) =>
      _remove(SessionForcedLogout<D>(expired: expired));

  Future<void> _remove(SessionState<D> transition) {
    _ensureOpen();
    final completer = Completer<void>();
    _tail = _tail
        .then((_) async {
          _ensureOpen();
          if (!_slot.hasCurrent) {
            _states.transition(SessionSignedOut<D>());
            completer.complete();
            return;
          }
          await _waitForRouteRemoval(transition);
          await _slot.clearCurrent();
          _current = null;
          _states.transition(SessionSignedOut<D>());
          _diagnostics?.emit(
            DartitectDiagnosticPhase.updated,
            generation: _slot.generation,
          );
          completer.complete();
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        });
    return completer.future;
  }

  Future<void> _waitForRouteRemoval(SessionState<D> transition) {
    final removal = Completer<void>();
    _routeRemoval = removal;
    _routeRemovalId = ++_transitionId;
    _states.transition(transition);
    return removal.future;
  }

  /// Confirms that routes borrowing the previous runtime were removed.
  bool confirmRoutesRemoved(int transitionId) {
    final removal = _routeRemoval;
    if (removal == null ||
        removal.isCompleted ||
        transitionId != _routeRemovalId) {
      return false;
    }
    _routeRemoval = null;
    _routeRemovalId = null;
    removal.complete();
    return true;
  }

  void _ensureOpen() {
    if (_closing) throw StateError('SessionRuntimeController is disposed.');
  }

  /// Stops transitions, releases pending gates, and drains the session graph.
  @override
  Future<void> disposeAsync() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    if (_closing) return;
    _closing = true;
    final removal = _routeRemoval;
    _routeRemoval = null;
    _routeRemovalId = null;
    if (removal != null && !removal.isCompleted) removal.complete();
    await _tail;
    await _slot.disposeAsync();
    _current = null;
    _states.dispose();
    _diagnostics?.emit(
      DartitectDiagnosticPhase.disposed,
      generation: _slot.generation,
    );
  }
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

  /// Router boundary that resolves only after old routes are gone.
  final SessionRouteRemover removeRoutes;

  /// Anonymous and fully signed-out subtree.
  final WidgetBuilder anonymous;

  /// Transition subtree, which must not borrow the old runtime.
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
    final id = _controller.pendingRouteRemovalId;
    if (id == null || id == _removingId) return;
    _removingId = id;
    unawaited(
      widget.removeRoutes(id).then<void>((_) {
        _controller.confirmRoutesRemoved(id);
        if (_removingId == id) _removingId = null;
      }, onError: _report),
    );
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
      SessionForcedLogout<D>() => widget.transitioning(context, state),
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
