import 'dart:async';
import 'dart:collection';

import 'package:dartitect/dartitect.dart';

import 'context.dart';
import 'errors.dart';
import 'logging.dart';
import 'redactor.dart';
import 'sampling.dart';
import 'tracing.dart';

/// Ownership declaration for one log destination.
final class LogSinkRegistration {
  const LogSinkRegistration._(this.sink, this.isOwned, this.filter);

  /// The runtime flushes and disposes this sink.
  const LogSinkRegistration.owned(LogSink sink, {LogSinkFilter? filter})
    : this._(sink, true, filter);

  /// The runtime flushes but never disposes this sink.
  const LogSinkRegistration.borrowed(LogSink sink, {LogSinkFilter? filter})
    : this._(sink, false, filter);

  /// Registered sink.
  final LogSink sink;

  /// Whether the runtime owns destination disposal.
  final bool isOwned;

  /// Optional destination-specific routing.
  final LogSinkFilter? filter;
}

/// Mutable counters that never feed back into observability dispatch.
final class ObservabilityDiagnostics {
  /// Events rejected by queue capacity.
  int droppedEvents = 0;

  /// Events removed by sampling.
  int sampledOutEvents = 0;

  /// Lazy message builders that crashed.
  int messageBuilderFailures = 0;

  /// Context attributes removed by the deny-by-default allowlist.
  int deniedContextAttributes = 0;

  /// Sink calls that failed.
  int sinkFailures = 0;

  /// Reporter calls that failed.
  int reporterFailures = 0;

  /// Tracer calls that failed.
  int tracerFailures = 0;

  /// Flushes that exceeded their timeout.
  int flushTimeouts = 0;
}

/// Explicit owner of logging, reporting, tracing, queueing, and flush.
///
/// The runtime is never global. Create one per app/session/headless composition
/// and reconstruct it inside each isolate.
final class ObservabilityRuntime implements AsyncDisposable {
  /// Creates a runtime with local developer logging and remote telemetry off.
  ObservabilityRuntime({
    Iterable<LogSinkRegistration>? logSinks,
    ErrorReporter? errorReporter,
    bool ownsErrorReporter = false,
    Tracer? tracer,
    bool ownsTracer = false,
    Redactor redactor = const Redactor(),
    SamplingPolicy? samplingPolicy,
    Set<String> allowedContextKeys = const <String>{},
    this.queueCapacity = 256,
    DateTime Function()? clock,
  }) : _sinks = List<LogSinkRegistration>.unmodifiable(
         logSinks ??
             const <LogSinkRegistration>[
               LogSinkRegistration.owned(DeveloperLogSink()),
             ],
       ),
       _destinationReporter = errorReporter,
       _ownsErrorReporter = ownsErrorReporter,
       _destinationTracer = tracer ?? NoOpTracer(),
       _ownsTracer = ownsTracer,
       _redactor = redactor,
       _sampling = samplingPolicy ?? FixedSamplingPolicy(),
       _allowedContextKeys = Set<String>.unmodifiable(allowedContextKeys),
       _clock = clock ?? DateTime.now {
    if (queueCapacity <= 0) {
      throw ArgumentError.value(queueCapacity, 'queueCapacity', 'must be > 0');
    }
    logger = _RuntimeLogger(this);
    reporter = _RuntimeReporter(this);
    tracing = _RuntimeTracer(this);
  }

  final List<LogSinkRegistration> _sinks;
  final ErrorReporter? _destinationReporter;
  final bool _ownsErrorReporter;
  final Tracer _destinationTracer;
  final bool _ownsTracer;
  final Redactor _redactor;
  final SamplingPolicy _sampling;
  final Set<String> _allowedContextKeys;
  final DateTime Function() _clock;
  final Queue<Future<void> Function()> _queue =
      Queue<Future<void> Function()>();

  /// Maximum queued dispatch operations.
  final int queueCapacity;

  /// Runtime-local logger.
  late final DartitectLogger logger;

  /// Runtime-local reporter. It is a no-op when no destination was configured.
  late final ErrorReporter reporter;

  /// Runtime-local tracer. It is disabled by default through sampling.
  late final Tracer tracing;

  /// Failure and overflow counters kept out-of-band to prevent recursion.
  final ObservabilityDiagnostics diagnostics = ObservabilityDiagnostics();

  Completer<void>? _idle;
  Future<void>? _disposal;
  bool _draining = false;
  bool _accepting = true;
  bool _disposed = false;

  /// Whether disposal has completed.
  bool get isDisposed => _disposed;

  void _log(
    LogLevel level,
    String message, {
    ObservabilityContext? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _event(
      ObservabilityLogEvent(
        name: ObservabilityEventName('legacy.log'),
        level: level,
        message: () => message,
        context: context,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  void _event(ObservabilityLogEvent input) {
    if (!_accepting) return;
    final timestamp = _clock().toUtc();
    final sanitizedContext = _sanitizeContext(input.context);
    final probe = LogEvent(
      timestamp: timestamp,
      name: input.name,
      level: input.level,
      message: '',
      context: sanitizedContext,
    );
    if (!_sampling.shouldSampleLog(probe)) {
      diagnostics.sampledOutEvents += 1;
      return;
    }
    final String message;
    try {
      message = input.message();
    } on Object {
      diagnostics.messageBuilderFailures += 1;
      return;
    }
    final sanitized = LogEvent(
      timestamp: timestamp,
      name: input.name,
      level: input.level,
      message: '${_redactor.sanitize(message)}',
      context: sanitizedContext,
      error: input.error == null ? null : _redactor.sanitizeError(input.error!),
      stackTrace: input.stackTrace == null
          ? null
          : _redactor.sanitizeStackTrace(input.stackTrace!),
    );
    _enqueue(() async {
      for (final registration in _sinks) {
        try {
          if (registration.filter?.allows(sanitized) == false) continue;
        } on Object {
          diagnostics.sinkFailures += 1;
          continue;
        }
        try {
          await registration.sink.emit(sanitized);
        } on Object {
          diagnostics.sinkFailures += 1;
        }
      }
    });
  }

  void _report(ErrorEvent event) {
    if (!_accepting || _destinationReporter == null) return;
    final sanitized = ErrorEvent(
      timestamp: event.timestamp.toUtc(),
      error: _redactor.sanitizeError(event.error),
      stackTrace: _redactor.sanitizeStackTrace(event.stackTrace),
      severity: event.severity,
      mechanism: event.mechanism,
      handled: event.handled,
      fingerprint: <String>[
        for (final value in event.fingerprint) '${_redactor.sanitize(value)}',
      ],
      context: _sanitizeContext(event.context),
    );
    _enqueue(() async {
      try {
        await _destinationReporter.report(sanitized);
      } on Object {
        diagnostics.reporterFailures += 1;
      }
    });
  }

  ObservabilityContext _sanitizeContext(ObservabilityContext? context) {
    final attributes = context?.attributes ?? const <String, Object?>{};
    final allowed = <String, Object?>{};
    for (final entry in attributes.entries) {
      if (_allowedContextKeys.contains(entry.key)) {
        allowed[entry.key] = entry.value;
      } else {
        diagnostics.deniedContextAttributes += 1;
      }
    }
    return ObservabilityContext(
      traceContext: switch (context?.traceContext) {
        final trace? => TraceContext(
          traceId: trace.traceId,
          spanId: trace.spanId,
          traceFlags: trace.traceFlags,
        ),
        null => null,
      },
      attributes: _redactor.sanitizeAttributes(allowed),
    );
  }

  void _enqueue(Future<void> Function() dispatch) {
    if (!_accepting) return;
    if (_queue.length >= queueCapacity) {
      diagnostics.droppedEvents += 1;
      return;
    }
    _queue.add(dispatch);
    _idle ??= Completer<void>();
    if (!_draining) {
      _draining = true;
      scheduleMicrotask(_drain);
    }
  }

  Future<void> _drain() async {
    while (_queue.isNotEmpty) {
      final dispatch = _queue.removeFirst();
      try {
        await dispatch();
      } on Object {
        // Each dispatch isolates its own destination failures. This final
        // boundary protects the queue from malformed custom implementations.
        diagnostics.sinkFailures += 1;
      }
    }
    _draining = false;
    _idle?.complete();
    _idle = null;
    if (_queue.isNotEmpty && !_draining) {
      _draining = true;
      scheduleMicrotask(_drain);
    }
  }

  /// Drains the queue and all destinations within [timeout].
  ///
  /// Returns false instead of throwing when the timeout expires. Destination
  /// failures are isolated and counted in [diagnostics].
  Future<bool> flush(Duration timeout) async {
    Future<void> drainAndFlush() async {
      await (_idle?.future ?? Future<void>.value());
      for (final registration in _sinks) {
        try {
          await registration.sink.flush();
        } on Object {
          diagnostics.sinkFailures += 1;
        }
      }
      if (_destinationReporter != null) {
        try {
          await _destinationReporter.flush();
        } on Object {
          diagnostics.reporterFailures += 1;
        }
      }
      try {
        await _destinationTracer.flush();
      } on Object {
        diagnostics.tracerFailures += 1;
      }
    }

    try {
      await drainAndFlush().timeout(timeout);
      return true;
    } on TimeoutException {
      diagnostics.flushTimeouts += 1;
      return false;
    }
  }

  /// Idempotently stops intake, flushes, and disposes owned destinations.
  @override
  Future<void> disposeAsync() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _accepting = false;
    await flush(const Duration(seconds: 5));
    for (final registration in _sinks.reversed) {
      if (!registration.isOwned) continue;
      try {
        await registration.sink.dispose();
      } on Object {
        diagnostics.sinkFailures += 1;
      }
    }
    if (_ownsErrorReporter && _destinationReporter != null) {
      try {
        await _destinationReporter.dispose();
      } on Object {
        diagnostics.reporterFailures += 1;
      }
    }
    if (_ownsTracer) {
      try {
        await _destinationTracer.dispose();
      } on Object {
        diagnostics.tracerFailures += 1;
      }
    }
    _disposed = true;
  }
}

final class _RuntimeLogger extends DartitectLogger {
  const _RuntimeLogger(this.runtime);

  final ObservabilityRuntime runtime;

  @override
  void event(ObservabilityLogEvent event) => runtime._event(event);

  @override
  void log(
    LogLevel level,
    String message, {
    ObservabilityContext? context,
    Object? error,
    StackTrace? stackTrace,
  }) => runtime._log(
    level,
    message,
    context: context,
    error: error,
    stackTrace: stackTrace,
  );
}

final class _RuntimeReporter extends ErrorReporter {
  const _RuntimeReporter(this.runtime);

  final ObservabilityRuntime runtime;

  @override
  void report(ErrorEvent event) => runtime._report(event);

  @override
  Future<void> flush() async {}

  @override
  Future<void> dispose() async {}
}

final class _RuntimeTracer extends Tracer {
  _RuntimeTracer(this.runtime);

  final ObservabilityRuntime runtime;
  final NoOpTracer _noOp = NoOpTracer();

  @override
  Span startSpan(
    String name, {
    TraceContext? parent,
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {
    final sanitizedName = '${runtime._redactor.sanitize(name)}';
    if (!runtime._accepting ||
        !runtime._sampling.shouldSampleSpan(sanitizedName)) {
      return _noOp.startSpan(sanitizedName, parent: parent, kind: kind);
    }
    try {
      return _SanitizingSpan(
        runtime._destinationTracer.startSpan(
          sanitizedName,
          parent: parent,
          kind: kind,
          attributes: runtime._redactor.sanitizeAttributes(attributes),
        ),
        runtime,
      );
    } on Object {
      runtime.diagnostics.tracerFailures += 1;
      return _noOp.startSpan(sanitizedName, parent: parent, kind: kind);
    }
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> dispose() async {}
}

final class _SanitizingSpan extends Span {
  _SanitizingSpan(this._delegate, this._runtime);

  final Span _delegate;
  final ObservabilityRuntime _runtime;
  bool _ended = false;

  @override
  TraceContext get context => _delegate.context;

  @override
  bool get isEnded => _ended || _delegate.isEnded;

  @override
  void addEvent(
    String name, {
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {
    if (isEnded) return;
    try {
      _delegate.addEvent(
        '${_runtime._redactor.sanitize(name)}',
        attributes: _runtime._redactor.sanitizeAttributes(attributes),
      );
    } on Object {
      _runtime.diagnostics.tracerFailures += 1;
    }
  }

  @override
  void setAttribute(String key, Object? value) {
    if (isEnded) return;
    try {
      _delegate.setAttribute(key, _runtime._redactor.sanitize(value, key: key));
    } on Object {
      _runtime.diagnostics.tracerFailures += 1;
    }
  }

  @override
  Future<void> end({
    SpanStatus status = SpanStatus.unset,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    if (isEnded) return;
    _ended = true;
    try {
      await _delegate.end(
        status: status,
        error: error == null ? null : _runtime._redactor.sanitizeError(error),
        stackTrace: stackTrace == null
            ? null
            : _runtime._redactor.sanitizeStackTrace(stackTrace),
      );
    } on Object {
      _runtime.diagnostics.tracerFailures += 1;
    }
  }
}
