import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:flutter/foundation.dart';

import 'command/command.dart';

/// Reports an unexpected ViewModel crash without changing its control flow.
abstract interface class DartitectViewModelCrashReporter {
  /// Reports [error] with its original [stackTrace] and non-secret [operation].
  FutureOr<void> report(
    Object error,
    StackTrace stackTrace, {
    required String operation,
  });
}

/// Callback-backed ViewModel crash reporter.
final class CallbackDartitectViewModelCrashReporter
    implements DartitectViewModelCrashReporter {
  /// Creates a reporter around [callback].
  const CallbackDartitectViewModelCrashReporter(this.callback);

  /// Consumer-owned crash reporting bridge.
  final FutureOr<void> Function(
    Object error,
    StackTrace stackTrace, {
    required String operation,
  })
  callback;

  @override
  FutureOr<void> report(
    Object error,
    StackTrace stackTrace, {
    required String operation,
  }) => callback(error, stackTrace, operation: operation);
}

/// Reporter that deliberately ignores unexpected ViewModel crashes.
final class NoOpDartitectViewModelCrashReporter
    implements DartitectViewModelCrashReporter {
  /// Creates a no-op reporter.
  const NoOpDartitectViewModelCrashReporter();

  @override
  void report(
    Object error,
    StackTrace stackTrace, {
    required String operation,
  }) {}
}

/// Base for a Flutter ViewModel that centrally owns commands and resources.
///
/// Owned resources are released once in reverse acquisition order. Forwarded
/// listeners are detached synchronously when shutdown starts, before command
/// cancellation and draining. Use [forward] for borrowed listenables and [own]
/// only for values whose lifecycle belongs to this ViewModel.
abstract class DartitectViewModel extends ChangeNotifier
    implements AsyncDisposable {
  /// Creates an empty ViewModel owner.
  DartitectViewModel({
    DartitectViewModelCrashReporter crashReporter =
        const NoOpDartitectViewModelCrashReporter(),
    DartitectDiagnosticSubject? diagnostics,
  }) : _crashReporter = crashReporter,
       _diagnostics = diagnostics {
    if (diagnostics != null &&
        diagnostics.kind != DartitectDiagnosticSubjectKind.owner) {
      throw ArgumentError.value(
        diagnostics.kind,
        'diagnostics',
        'DartitectViewModel requires an owner diagnostic subject.',
      );
    }
  }

  final DartitectViewModelCrashReporter _crashReporter;
  final DartitectDiagnosticSubject? _diagnostics;
  final List<_ViewModelOwnedResource> _resources = <_ViewModelOwnedResource>[];
  final List<_ViewModelForwarding> _forwardings = <_ViewModelForwarding>[];

  Future<void>? _disposal;
  bool _isDisposing = false;
  bool _isDisposed = false;
  bool _notifierDisposed = false;

  /// Reporter failures isolated from the original crash or cleanup path.
  int reporterFailureCount = 0;

  /// Number of resources whose cleanup is still owned by this ViewModel.
  int get ownedResourceCount => _resources.length;

  /// Number of currently attached notification-forwarding listeners.
  int get forwardedListenerCount => _forwardings.length;

  /// Whether shutdown has started but resource cleanup has not finished.
  bool get isDisposing => _isDisposing && !_isDisposed;

  /// Whether cleanup has been attempted for every owned resource.
  bool get isDisposed => _isDisposed;

  /// Owns a command and forwards its state notifications to this ViewModel.
  ///
  /// The static bound guarantees both listenability and asynchronous draining.
  T ownCommand<T extends DartitectObservableResource>(
    T command, {
    String? label,
  }) {
    return own<T>(
      command,
      (value) => value.disposeAsync(),
      listenable: command,
      label: label ?? 'command#${_resources.length + 1}',
    );
  }

  /// Owns [resource], optionally forwarding [listenable] notifications.
  ///
  /// [release] is attempted exactly once. Registration is rejected after
  /// shutdown begins. Labels are diagnostic metadata and must not contain
  /// credentials, domain values, or other sensitive data.
  T own<T extends Object>(
    T resource,
    FutureOr<void> Function(T resource) release, {
    Listenable? listenable,
    String? label,
  }) {
    _ensureActive();
    final resourceLabel = _validatedLabel(
      label ?? 'resource#${_resources.length + 1}',
    );
    if (listenable != null) {
      _attach(listenable, resourceLabel);
    }
    _resources.add(
      _ViewModelOwnedResource(() => release(resource), resourceLabel),
    );
    _diagnostics?.emit(
      DartitectDiagnosticPhase.updated,
      revision: _resources.length,
    );
    return resource;
  }

  /// Forwards [listenable] without taking ownership of it.
  T forward<T extends Listenable>(T listenable, {String? label}) {
    _ensureActive();
    _attach(
      listenable,
      _validatedLabel(label ?? 'listenable#${_forwardings.length + 1}'),
    );
    return listenable;
  }

  /// Runs [body], reports an unexpected crash, then rethrows the same object.
  ///
  /// This is for unexpected exceptions at ViewModel-specific async boundaries;
  /// expected application failures remain typed command results.
  @protected
  Future<T> runReportingCrashes<T>(
    String operation,
    FutureOr<T> Function() body,
  ) async {
    final operationLabel = _validatedLabel(operation);
    try {
      return await body();
    } catch (error, stackTrace) {
      _diagnostics?.emit(DartitectDiagnosticPhase.crashed);
      _reportCrash(error, stackTrace, operation: operationLabel);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Detaches listeners, then releases all owned resources in LIFO order.
  ///
  /// Concurrent and repeated calls share one completion. Cleanup continues
  /// after individual failures and throws a [ResourceCleanupException] after
  /// every resource has been attempted.
  @override
  Future<void> disposeAsync() {
    final existing = _disposal;
    if (existing != null) return existing;

    final completer = Completer<void>();
    _disposal = completer.future;
    _isDisposing = true;
    _diagnostics?.emit(
      DartitectDiagnosticPhase.started,
      revision: _resources.length,
    );
    final listenerFailures = _detachAll();
    if (!_notifierDisposed) {
      _notifierDisposed = true;
      super.dispose();
    }
    unawaited(_completeDisposal(completer, listenerFailures));
    return completer.future;
  }

  @override
  // ChangeNotifier is disposed synchronously by disposeAsync before draining.
  // ignore: must_call_super
  void dispose() {
    final disposal = disposeAsync();
    unawaited(
      disposal.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
  }

  void _ensureActive() {
    if (_isDisposing || _isDisposed) {
      throw StateError(
        'DartitectViewModel is shutting down and cannot own new resources.',
      );
    }
  }

  String _validatedLabel(String label) {
    if (label.trim().isEmpty) {
      throw ArgumentError.value(label, 'label', 'Must not be blank.');
    }
    return label;
  }

  void _attach(Listenable listenable, String label) {
    final forwarding = _ViewModelForwarding(
      listenable,
      _forwardNotification,
      label,
    );
    listenable.addListener(forwarding.listener);
    _forwardings.add(forwarding);
  }

  void _forwardNotification() {
    if (_isDisposing || _isDisposed) return;
    notifyListeners();
  }

  List<ResourceCleanupFailure> _detachAll() {
    final failures = <ResourceCleanupFailure>[];
    for (final forwarding in _forwardings.reversed) {
      try {
        forwarding.listenable.removeListener(forwarding.listener);
      } catch (error, stackTrace) {
        failures.add(
          ResourceCleanupFailure(
            resourceLabel: '${forwarding.label}.listener',
            error: error,
            stackTrace: stackTrace,
          ),
        );
        _diagnostics?.emit(DartitectDiagnosticPhase.crashed);
        _reportCrash(
          error,
          stackTrace,
          operation: '${forwarding.label}.listener',
        );
      }
    }
    _forwardings.clear();
    return failures;
  }

  Future<void> _completeDisposal(
    Completer<void> completer,
    List<ResourceCleanupFailure> failures,
  ) async {
    try {
      for (final resource in _resources.reversed) {
        try {
          await resource.release();
        } catch (error, stackTrace) {
          failures.add(
            ResourceCleanupFailure(
              resourceLabel: resource.label,
              error: error,
              stackTrace: stackTrace,
            ),
          );
          _diagnostics?.emit(DartitectDiagnosticPhase.crashed);
          _reportCrash(error, stackTrace, operation: resource.label);
        }
      }
    } finally {
      _resources.clear();
      _isDisposing = false;
      _isDisposed = true;
      _diagnostics?.emit(DartitectDiagnosticPhase.disposed);
    }

    if (failures.isEmpty) {
      completer.complete();
    } else {
      completer.completeError(ResourceCleanupException(failures));
    }
  }

  void _reportCrash(
    Object error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    try {
      final report = _crashReporter.report(
        error,
        stackTrace,
        operation: operation,
      );
      if (report is Future<void>) {
        unawaited(
          report.then<void>(
            (_) {},
            onError: (Object _, StackTrace __) {
              reporterFailureCount += 1;
            },
          ),
        );
      }
    } on Object {
      reporterFailureCount += 1;
    }
  }
}

final class _ViewModelOwnedResource(
  final FutureOr<void> Function() release,
  final String label,
);

final class _ViewModelForwarding(
  final Listenable listenable,
  final VoidCallback listener,
  final String label,
);
