import 'dart:async';

import 'package:dartitect/dartitect.dart';

/// Explicit graph lifetime exercised by [OwnedScopeHarness].
enum OwnedScopeKind {
  /// Process/application composition.
  application,

  /// One authentication/session generation.
  session,

  /// State shared deliberately by multiple routes.
  feature,

  /// One route/ViewModel composition.
  route,

  /// One admitted command/resource attempt.
  operation,

  /// One receiver-local isolate graph.
  isolate,
}

/// Observable result of one owned scope exercise.
final class OwnedScopeHarnessResult<T> {
  /// Creates a scope harness result.
  const OwnedScopeHarnessResult({
    required this.kind,
    required this.activeOperationsAfterDispose,
    required this.disposed,
    this.value,
    this.error,
    this.stackTrace,
  });

  /// Lifetime under test.
  final OwnedScopeKind kind;

  /// Body result when successful.
  final T? value;

  /// Original create/use/dispose error.
  final Object? error;

  /// Stack captured with [error].
  final StackTrace? stackTrace;

  /// Residual admitted operations after cleanup.
  final int activeOperationsAfterDispose;

  /// Whether graph cleanup completed.
  final bool disposed;
}

/// Exercises any application/session/feature/route/operation/isolate graph
/// through public [ResourceTransaction] and [OwnedGraph] contracts.
final class OwnedScopeHarness<R extends Object> {
  /// Creates a harness for [kind] with a transactionally built root.
  const OwnedScopeHarness({required this.kind, required this.create});

  /// Declared graph lifetime.
  final OwnedScopeKind kind;

  /// Consumer-injected graph builder.
  final FutureOr<R> Function(ResourceTransaction transaction) create;

  /// Builds, admits [body], drains, and disposes the graph.
  Future<OwnedScopeHarnessResult<T>> run<T>(
    FutureOr<T> Function(R root) body,
  ) async {
    OwnedGraph<R>? graph;
    T? value;
    Object? error;
    StackTrace? stackTrace;
    try {
      graph = await ResourceTransaction.create<R>(
        create,
        label: 'OwnedScopeHarness.${kind.name}',
      );
      value = await graph.use(body);
    } catch (caught, caughtStack) {
      error = caught;
      stackTrace = caughtStack;
    } finally {
      try {
        await graph?.disposeAsync();
      } catch (caught, caughtStack) {
        error ??= caught;
        stackTrace ??= caughtStack;
      }
    }
    return OwnedScopeHarnessResult<T>(
      kind: kind,
      value: value,
      error: error,
      stackTrace: stackTrace,
      activeOperationsAfterDispose: graph?.activeOperationCount ?? 0,
      disposed: graph?.isDisposed ?? error != null,
    );
  }
}
