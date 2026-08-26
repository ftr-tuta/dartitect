// Observer failures are deliberately isolated from owned client lifecycle.
// ignore_for_file: dartitect_empty_catch

import 'package:dartitect/dartitect.dart';
import 'package:dio/dio.dart';

/// Explicitly owns or borrows a real [Dio] client.
final class DioOwner implements Disposable {
  /// Creates and owns a client.
  ///
  /// [interceptors] are installed in iteration order. [configure] runs after
  /// interceptor installation and may replace the adapter. If configuration
  /// fails, the partially configured client is force-closed.
  factory DioOwner.create({
    BaseOptions? options,
    Iterable<Interceptor> interceptors = const <Interceptor>[],
    void Function(Dio dio)? configure,
    Dio Function(BaseOptions options)? clientFactory,
    ArchitectureObserver observer = const NoOpArchitectureObserver(),
    bool forceClose = false,
  }) {
    final resolvedOptions = options ?? BaseOptions();
    final Dio dio;
    if (clientFactory case final factory?) {
      dio = factory(resolvedOptions);
    } else {
      dio = Dio(resolvedOptions);
    }
    try {
      dio.interceptors.addAll(interceptors);
      configure?.call(dio);
      return DioOwner._(
        dio,
        ownsClient: true,
        forceClose: forceClose,
        observer: observer,
      );
    } catch (_) {
      dio.close(force: true);
      rethrow;
    }
  }

  /// Borrows [value]. Disposing this owner never closes the client.
  factory DioOwner.value(
    Dio value, {
    ArchitectureObserver observer = const NoOpArchitectureObserver(),
  }) => DioOwner._(
    value,
    ownsClient: false,
    forceClose: false,
    observer: observer,
  );

  DioOwner._(
    this._dio, {
    required bool ownsClient,
    required bool forceClose,
    required ArchitectureObserver observer,
  }) : _ownsClient = ownsClient,
       _forceClose = forceClose,
       _observer = observer {
    _emit(ArchitectureEventKind.resourceAcquired);
  }

  final Dio _dio;
  final bool _ownsClient;
  final bool _forceClose;
  final ArchitectureObserver _observer;
  bool _disposed = false;

  /// Owned or borrowed client, preserving the complete Dio API.
  Dio get dio {
    if (_disposed) {
      _emit(ArchitectureEventKind.operationAfterDispose);
      throw StateError('DioOwner has been disposed.');
    }
    return _dio;
  }

  /// Whether this wrapper owns and closes its client.
  bool get ownsClient => _ownsClient;

  /// Whether wrapper disposal has completed.
  bool get isDisposed => _disposed;

  /// Closes only an owned client. Repeated calls are harmless.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_ownsClient) {
      try {
        _dio.close(force: _forceClose);
        _emit(ArchitectureEventKind.resourceReleased);
      } catch (error, stackTrace) {
        _emit(
          ArchitectureEventKind.resourceReleaseFailed,
          error: error,
          stackTrace: stackTrace,
        );
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
  }

  void _emit(
    ArchitectureEventKind kind, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    try {
      _observer.onEvent(
        ArchitectureEvent(
          kind,
          source: 'DioOwner',
          label: _ownsClient ? 'owned' : 'borrowed',
          error: error,
          stackTrace: stackTrace,
        ),
      );
    } on Object {
      // Optional diagnostics cannot change client lifecycle.
    }
  }
}

/// Creates and owns a cooperative Dio cancellation token.
CancelToken ownCancelToken(
  ResourceOwner owner, {
  Object reason = 'Owner disposed',
}) => owner.own(
  CancelToken(),
  (token) => token.cancel(reason),
  label: 'Dio CancelToken',
);
