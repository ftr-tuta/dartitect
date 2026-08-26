import 'dart:async';
import 'dart:ui';

import 'package:dartitect/dartitect.dart';
import 'package:flutter/foundation.dart';

/// Static Flutter crash boundary where an error originated.
enum FlutterCrashMechanism {
  /// Flutter framework callback.
  flutterFramework,

  /// Platform dispatcher callback.
  platformDispatcher,

  /// Guarded foreground zone.
  zone,
}

/// Provider-neutral crash callback injected by the composition root.
abstract interface class FlutterCrashReporter {
  /// Reports one unexpected crash without changing its control flow.
  FutureOr<void> report(
    Object error,
    StackTrace stackTrace,
    FlutterCrashMechanism mechanism,
  );
}

/// Callback-backed Flutter crash reporter.
final class CallbackFlutterCrashReporter implements FlutterCrashReporter {
  /// Creates a reporter around [callback].
  const CallbackFlutterCrashReporter(this.callback);

  /// Consumer-owned reporting bridge.
  final FutureOr<void> Function(
    Object error,
    StackTrace stackTrace,
    FlutterCrashMechanism mechanism,
  )
  callback;

  @override
  FutureOr<void> report(
    Object error,
    StackTrace stackTrace,
    FlutterCrashMechanism mechanism,
  ) => callback(error, stackTrace, mechanism);
}

/// Reporter that deliberately ignores Flutter crashes.
final class NoOpFlutterCrashReporter implements FlutterCrashReporter {
  /// Creates a no-op reporter.
  const NoOpFlutterCrashReporter();

  @override
  void report(
    Object error,
    StackTrace stackTrace,
    FlutterCrashMechanism mechanism,
  ) {}
}

/// Installs composition-owned Flutter, platform, and zone error boundaries.
///
/// Previous global handlers are chained and restored. Install only at the
/// foreground composition root; headless isolates must create their own Dart
/// observability runtime without this UI binding.
final class FlutterErrorBinding implements Disposable {
  FlutterErrorBinding._({
    required FlutterCrashReporter reporter,
    required PlatformDispatcher dispatcher,
  }) : _reporter = reporter,
       _dispatcher = dispatcher,
       _previousFlutterHandler = FlutterError.onError,
       _previousPlatformHandler = dispatcher.onError {
    _flutterHandler = _handleFlutterError;
    _platformHandler = _handlePlatformError;
    FlutterError.onError = _flutterHandler;
    dispatcher.onError = _platformHandler;
  }

  /// Installs the process-global foreground handlers.
  factory FlutterErrorBinding.install({
    required FlutterCrashReporter reporter,
    PlatformDispatcher? dispatcher,
  }) {
    if (_active != null) {
      throw StateError('FlutterErrorBinding is already installed.');
    }
    final binding = FlutterErrorBinding._(
      reporter: reporter,
      dispatcher: dispatcher ?? PlatformDispatcher.instance,
    );
    _active = binding;
    return binding;
  }

  static FlutterErrorBinding? _active;

  final FlutterCrashReporter _reporter;
  final PlatformDispatcher _dispatcher;
  final FlutterExceptionHandler? _previousFlutterHandler;
  final ErrorCallback? _previousPlatformHandler;
  late final FlutterExceptionHandler _flutterHandler;
  late final ErrorCallback _platformHandler;

  bool _reporting = false;
  bool _disposed = false;

  /// Reporter failures isolated from the original error path.
  int reporterFailureCount = 0;

  /// Whether handlers have been restored.
  bool get isDisposed => _disposed;

  /// Runs [body] in a guarded zone and forwards uncaught errors after capture.
  ///
  /// The return value is intentionally void: use this around the synchronous
  /// foreground bootstrap that calls `runApp`. Async work spawned by the body
  /// remains covered by the zone.
  void runGuarded(
    void Function() body, {
    void Function(Object error, StackTrace stackTrace)? forward,
  }) {
    final parentZone = Zone.current;
    runZonedGuarded(body, (error, stackTrace) {
      _report(error, stackTrace, mechanism: FlutterCrashMechanism.zone);
      if (forward != null) {
        forward(error, stackTrace);
      } else {
        parentZone.handleUncaughtError(error, stackTrace);
      }
    });
  }

  void _handleFlutterError(FlutterErrorDetails details) {
    _report(
      details.exception,
      details.stack ?? StackTrace.current,
      mechanism: FlutterCrashMechanism.flutterFramework,
    );
    final previous = _previousFlutterHandler;
    if (previous != null) {
      previous(details);
    } else {
      FlutterError.presentError(details);
    }
  }

  bool _handlePlatformError(Object error, StackTrace stackTrace) {
    _report(
      error,
      stackTrace,
      mechanism: FlutterCrashMechanism.platformDispatcher,
    );
    return _previousPlatformHandler?.call(error, stackTrace) ?? false;
  }

  void _report(
    Object error,
    StackTrace stackTrace, {
    required FlutterCrashMechanism mechanism,
  }) {
    if (_disposed || _reporting) return;
    _reporting = true;
    try {
      final result = _reporter.report(error, stackTrace, mechanism);
      if (result is Future<void>) {
        unawaited(result.catchError((Object _, StackTrace _) {}));
      }
    } on Object {
      // Reporting cannot recurse into or replace the original error path.
      reporterFailureCount += 1;
    } finally {
      _reporting = false;
    }
  }

  /// Restores the handlers observed during installation.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (identical(FlutterError.onError, _flutterHandler)) {
      FlutterError.onError = _previousFlutterHandler;
    }
    if (identical(_dispatcher.onError, _platformHandler)) {
      _dispatcher.onError = _previousPlatformHandler;
    }
    if (identical(_active, this)) _active = null;
  }
}
