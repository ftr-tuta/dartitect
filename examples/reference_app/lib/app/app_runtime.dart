import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_observability/dartitect_observability.dart';

import '../features/tasks/application/offline_first_task_session.dart';
import '../features/tasks/application/offline_task_store.dart';
import '../features/tasks/application/task_remote.dart';
import '../features/tasks/infrastructure/reference_task_remote.dart';
import '../features/tasks/infrastructure/task_store_factory.dart';

/// Application-owned dependency graph; no lookup container is involved.
final class AppRuntime implements AsyncDisposable, DartitectScopeValue {
  AppRuntime._(this.tasks, this.observability, this.architectureObserver)
    : sessionState = SessionStateController<ReferenceSessionDescription>(
        SessionActive<ReferenceSessionDescription>(
          generation: Object(),
          value: const ReferenceSessionDescription(),
        ),
      );

  /// Opens the platform store and creates the complete application graph.
  static Future<AppRuntime> create({
    String? directoryPath,
    bool forceMemory = false,
    OfflineTaskStore? store,
    TaskRemote? remote,
  }) async {
    final observability = ObservabilityRuntime(
      samplingPolicy: FixedSamplingPolicy(spanRate: 1),
    );
    final observer = ArchitectureObserverBridge(
      logger: observability.logger,
      tracer: observability.tracing,
    );
    final selectedStore =
        store ??
        await openOfflineTaskStore(
          directoryPath: directoryPath,
          forceMemory: forceMemory,
        );
    try {
      final tasks = await LocalFirstTaskRepository.create(
        store: selectedStore,
        remote: remote ?? ReferenceTaskRemote(),
      );
      observability.logger.info('Reference runtime created.');
      return AppRuntime._(tasks, observability, observer);
    } catch (_) {
      await selectedStore.disposeAsync();
      await observer.disposeAsync();
      await observability.disposeAsync();
      rethrow;
    }
  }

  /// Task feature's owned offline-first session.
  final LocalFirstTaskRepository tasks;

  /// Application-owned local observability runtime.
  final ObservabilityRuntime observability;

  /// Bridge that observes architecture lifecycle events.
  final ArchitectureObserverBridge architectureObserver;

  /// Replayable application-shell state for the current session generation.
  final SessionStateController<ReferenceSessionDescription> sessionState;

  final Object _scopeIdentity = Object();

  @override
  Object get scopeIdentity => _scopeIdentity;

  /// Closes route admission without retaining a `BuildContext`.
  void requestForcedLogout({bool expired = false}) {
    if (sessionState.isDisposed ||
        sessionState.value
            is SessionForcedLogout<ReferenceSessionDescription> ||
        sessionState.value is SessionSignedOut<ReferenceSessionDescription>) {
      return;
    }
    sessionState.transition(
      SessionForcedLogout<ReferenceSessionDescription>(expired: expired),
    );
  }

  Future<void>? _sessionCloseFuture;
  Completer<void>? _authenticatedRoutesRemoved;

  /// Arms the route-removal fence for the current authenticated shell.
  void markAuthenticatedRoutesMounted() {
    if (_authenticatedRoutesRemoved?.isCompleted == false) return;
    _authenticatedRoutesRemoved = Completer<void>();
  }

  /// Confirms that the authenticated feature subtree has left the widget tree.
  void confirmAuthenticatedRoutesRemoved() {
    final removed = _authenticatedRoutesRemoved;
    if (removed != null && !removed.isCompleted) removed.complete();
  }

  /// Drains the session graph after the shell has removed authenticated routes.
  Future<void> completeForcedLogout() =>
      _sessionCloseFuture ??= _closeSession();

  Future<void> _closeSession() async {
    await _authenticatedRoutesRemoved?.future;
    await tasks.disposeAsync();
    if (!sessionState.isDisposed) {
      sessionState.transition(
        const SessionSignedOut<ReferenceSessionDescription>(),
      );
    }
  }

  /// Flutter crash bridge kept at the application composition root.
  FlutterCrashReporter get flutterCrashReporter =>
      CallbackFlutterCrashReporter((error, stackTrace, mechanism) async {
        await observability.reporter.report(
          ErrorEvent(
            timestamp: DateTime.now().toUtc(),
            error: error,
            stackTrace: stackTrace,
            mechanism: switch (mechanism) {
              FlutterCrashMechanism.flutterFramework =>
                ErrorMechanism.flutterFramework,
              FlutterCrashMechanism.platformDispatcher =>
                ErrorMechanism.platformDispatcher,
              FlutterCrashMechanism.zone => ErrorMechanism.zone,
            },
            handled: false,
            fingerprint: <String>['flutter', mechanism.name],
          ),
        );
      });

  Future<void>? _disposeFuture;

  @override
  Future<void> disposeAsync() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    await (_sessionCloseFuture ??= _closeSession());
    sessionState.dispose();
    await architectureObserver.disposeAsync();
    await observability.disposeAsync();
  }
}

/// Immutable, deliberately identity-free description of the reference session.
final class ReferenceSessionDescription {
  /// Creates the single reference-app session description.
  const ReferenceSessionDescription();
}
