import 'dart:async';

import '../diagnostics/diagnostics_protocol.dart';
import '../observer.dart';
import 'contracts.dart';

/// A cleanup failure associated with one registered resource.
final class ResourceCleanupFailure {
  /// Creates a cleanup failure record.
  const ResourceCleanupFailure({
    required this.resourceLabel,
    required this.error,
    required this.stackTrace,
  });

  /// Stable, non-secret label assigned during ownership registration.
  final String resourceLabel;

  /// Error thrown by the release callback.
  final Object error;

  /// Stack trace captured at the release boundary.
  final StackTrace stackTrace;
}

/// Reports every cleanup failure while preserving their LIFO order.
final class ResourceCleanupException implements Exception {
  /// Creates an aggregate cleanup exception.
  ResourceCleanupException(Iterable<ResourceCleanupFailure> failures)
    : failures = List<ResourceCleanupFailure>.unmodifiable(failures) {
    if (this.failures.isEmpty) {
      throw ArgumentError.value(failures, 'failures', 'must not be empty');
    }
  }

  /// Failures in the order in which cleanup was attempted.
  final List<ResourceCleanupFailure> failures;

  /// The first cleanup error encountered.
  ResourceCleanupFailure get first => failures.first;

  @override
  String toString() =>
      'ResourceCleanupException(${failures.length} cleanup failure(s); '
      'first: ${first.resourceLabel}: ${first.error})';
}

/// Owns release callbacks and runs them once in reverse acquisition order.
///
/// A value registered with [own] is owned. Values merely passed to another
/// object are borrowed and must not be registered by that borrower. Once
/// shutdown starts, this owner rejects new registrations. Cleanup continues
/// after individual failures and reports all of them together.
///
/// Ownership applies to the live resource or handle. Persisted data survives
/// teardown unless its release callback explicitly implements a domain-level
/// deletion policy; temporary data must register its removal with its owner.
final class ResourceOwner implements AsyncDisposable {
  /// Creates a resource owner.
  ResourceOwner({
    ArchitectureObserver observer = const NoOpArchitectureObserver(),
    String label = 'ResourceOwner',
    DartitectDiagnosticSubject? diagnostics,
  }) : _observer = observer,
       _label = label,
       _diagnostics = diagnostics {
    if (diagnostics != null &&
        diagnostics.kind != DartitectDiagnosticSubjectKind.owner) {
      throw ArgumentError.value(
        diagnostics.kind,
        'diagnostics',
        'ResourceOwner requires an owner diagnostic subject.',
      );
    }
  }

  final ArchitectureObserver _observer;
  final String _label;
  final DartitectDiagnosticSubject? _diagnostics;
  final List<_OwnedResource<Object?>> _resources = <_OwnedResource<Object?>>[];

  Future<void>? _disposal;
  bool _isDisposing = false;
  bool _isDisposed = false;

  /// Observer failures isolated from lifecycle behavior.
  int observerFailureCount = 0;

  /// Whether shutdown has started but cleanup has not yet finished.
  bool get isDisposing => _isDisposing && !_isDisposed;

  /// Whether every registered cleanup has been attempted.
  bool get isDisposed => _isDisposed;

  /// Registers [value] as owned and returns it unchanged.
  ///
  /// Registration happens only after the caller has successfully acquired the
  /// value. [release] is called at most once. Use [label] for diagnostics; it
  /// must not contain credentials or object contents.
  T own<T>(T value, FutureOr<void> Function(T value) release, {String? label}) {
    if (_isDisposing || _isDisposed) {
      _emit(
        ArchitectureEvent(
          ArchitectureEventKind.operationAfterDispose,
          source: _label,
          label: label,
        ),
      );
      throw StateError(
        '$_label is shutting down and cannot own new resources.',
      );
    }

    final resourceLabel = label ?? 'resource#${_resources.length + 1}';
    _resources.add(
      _OwnedResource<Object?>(
        value,
        (ownedValue) => release(ownedValue as T),
        resourceLabel,
      ),
    );
    _diagnostics?.emit(
      DartitectDiagnosticPhase.updated,
      revision: _resources.length,
    );
    _emit(
      ArchitectureEvent(
        ArchitectureEventKind.resourceAcquired,
        source: _label,
        label: resourceLabel,
      ),
    );
    return value;
  }

  /// Releases all owned resources in LIFO order.
  ///
  /// Concurrent and repeated calls share the same completion. Every release
  /// callback is attempted even if an earlier callback fails.
  @override
  Future<void> disposeAsync() {
    final existing = _disposal;
    if (existing != null) {
      return existing;
    }

    final completer = Completer<void>();
    _disposal = completer.future;
    _isDisposing = true;
    _diagnostics?.emit(
      DartitectDiagnosticPhase.started,
      revision: _resources.length,
    );
    _emit(
      ArchitectureEvent(ArchitectureEventKind.runtimeDisposing, source: _label),
    );
    unawaited(_completeDisposal(completer));
    return completer.future;
  }

  Future<void> _completeDisposal(Completer<void> completer) async {
    try {
      await _disposeResources();
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
  }

  Future<void> _disposeResources() async {
    final failures = <ResourceCleanupFailure>[];
    try {
      for (final resource in _resources.reversed) {
        _emit(
          ArchitectureEvent(
            ArchitectureEventKind.resourceReleaseStarted,
            source: _label,
            label: resource.label,
          ),
        );
        try {
          await resource.release(resource.value);
          _emit(
            ArchitectureEvent(
              ArchitectureEventKind.resourceReleased,
              source: _label,
              label: resource.label,
            ),
          );
        } catch (error, stackTrace) {
          failures.add(
            ResourceCleanupFailure(
              resourceLabel: resource.label,
              error: error,
              stackTrace: stackTrace,
            ),
          );
          _emit(
            ArchitectureEvent(
              ArchitectureEventKind.resourceReleaseFailed,
              source: _label,
              label: resource.label,
              error: error,
              stackTrace: stackTrace,
            ),
          );
          _diagnostics?.emit(DartitectDiagnosticPhase.failed);
        }
      }
    } finally {
      _resources.clear();
      _isDisposed = true;
      _isDisposing = false;
      _emit(
        ArchitectureEvent(
          ArchitectureEventKind.runtimeDisposed,
          source: _label,
        ),
      );
      _diagnostics?.emit(DartitectDiagnosticPhase.disposed);
    }

    if (failures.isNotEmpty) {
      throw ResourceCleanupException(failures);
    }
  }

  void _emit(ArchitectureEvent event) {
    try {
      _observer.onEvent(event);
    } on Object {
      // Diagnostics are deliberately unable to alter lifecycle behavior.
      observerFailureCount += 1;
    }
  }
}

final class _OwnedResource<T>(
  final T value,
  final FutureOr<void> Function(T value) release,
  final String label,
);
