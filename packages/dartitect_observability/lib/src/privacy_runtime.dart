import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:dartitect/dartitect.dart';

import 'context.dart';
import 'errors.dart';
import 'logging.dart';
import 'privacy.dart';
import 'sampling.dart';
import 'sanitizer.dart';
import 'tracing.dart';

/// Capabilities supported by one prepared observability destination.
enum ObservabilityDestinationCapability {
  /// Receives prepared log events.
  logs,

  /// Receives prepared error events.
  errors,

  /// Creates spans exclusively from prepared tracing inputs.
  traces,
}

/// Prepared context whose constructor is private to the privacy runtime.
final class PreparedObservabilityContext {
  const PreparedObservabilityContext._({
    required this.traceContext,
    required this.attributes,
  });

  /// Validated protocol-only trace context.
  final TraceContext? traceContext;

  /// Deeply immutable sanitized attributes.
  final Map<String, Object?> attributes;
}

/// Prepared log event that cannot be constructed by destination packages.
final class PreparedLogEvent {
  const PreparedLogEvent._({
    required this.timestamp,
    required this.name,
    required this.level,
    required this.message,
    required this.context,
    required this.error,
    required this.stackTrace,
  });

  /// UTC event time.
  final DateTime timestamp;

  /// Validated low-cardinality event name.
  final ObservabilityEventName name;

  /// Event severity.
  final LogLevel level;

  /// Sanitized bounded message or a constant marker.
  final String message;

  /// Prepared trace correlation and attributes.
  final PreparedObservabilityContext context;

  /// Sanitized error structure or marker.
  final Object? error;

  /// Sanitized frame list or marker.
  final Object? stackTrace;
}

/// Prepared error event that cannot retain its original error object.
final class PreparedErrorEvent {
  const PreparedErrorEvent._({
    required this.timestamp,
    required this.error,
    required this.stackTrace,
    required this.severity,
    required this.mechanism,
    required this.handled,
    required this.fingerprint,
    required this.context,
  });

  /// UTC event time.
  final DateTime timestamp;

  /// Sanitized error structure or marker.
  final Object error;

  /// Sanitized frame list or marker.
  final Object stackTrace;

  /// Error severity.
  final ErrorSeverity severity;

  /// Boundary that observed the error.
  final ErrorMechanism mechanism;

  /// Whether application code handled the error.
  final bool handled;

  /// Immutable sanitized grouping hints.
  final List<String> fingerprint;

  /// Prepared trace correlation and attributes.
  final PreparedObservabilityContext context;
}

/// Prepared input for one destination span.
final class PreparedSpanStart {
  const PreparedSpanStart._({
    required this.name,
    required this.parent,
    required this.kind,
    required this.attributes,
  });

  /// Sanitized span name.
  final String name;

  /// Validated protocol-only parent context.
  final TraceContext? parent;

  /// Span kind.
  final SpanKind kind;

  /// Deeply immutable sanitized attributes.
  final Map<String, Object?> attributes;
}

/// Prepared span attribute.
final class PreparedSpanAttribute {
  const PreparedSpanAttribute._(this.key, this.value);

  /// Sanitized key.
  final String key;

  /// Sanitized immutable value.
  final Object? value;
}

/// Prepared span event.
final class PreparedSpanEvent {
  const PreparedSpanEvent._({required this.name, required this.attributes});

  /// Sanitized event name.
  final String name;

  /// Deeply immutable sanitized attributes.
  final Map<String, Object?> attributes;
}

/// Prepared span completion.
final class PreparedSpanEnd {
  const PreparedSpanEnd._({
    required this.status,
    required this.error,
    required this.stackTrace,
  });

  /// Final span status.
  final SpanStatus status;

  /// Sanitized error structure or marker.
  final Object? error;

  /// Sanitized frame list or marker.
  final Object? stackTrace;
}

/// Destination that accepts only runtime-prepared log events.
abstract class PreparedLogSink {
  /// Creates a prepared sink base.
  const PreparedLogSink();

  /// Emits one prepared event.
  FutureOr<void> emitPrepared(PreparedLogEvent event);

  /// Drains destination work.
  FutureOr<void> flush() {}

  /// Releases destination-owned resources.
  FutureOr<void> dispose() {}
}

/// Destination that accepts only runtime-prepared error events.
abstract class PreparedErrorReporter {
  /// Creates a prepared reporter base.
  const PreparedErrorReporter();

  /// Reports one prepared error.
  FutureOr<void> reportPrepared(PreparedErrorEvent event);

  /// Drains destination work.
  FutureOr<void> flush() {}

  /// Releases destination-owned resources.
  FutureOr<void> dispose() {}
}

/// Destination span created only from prepared tracing inputs.
abstract class PreparedSpan {
  /// Creates a prepared span base.
  const PreparedSpan();

  /// Trace identity propagated to children.
  TraceContext get context;

  /// Whether completion has begun.
  bool get isEnded;

  /// Sets one prepared attribute.
  void setPreparedAttribute(PreparedSpanAttribute attribute);

  /// Adds one prepared event.
  void addPreparedEvent(PreparedSpanEvent event);

  /// Completes the span once.
  FutureOr<void> endPrepared(PreparedSpanEnd end);
}

/// Destination tracer that accepts only prepared start inputs.
abstract class PreparedTracer {
  /// Creates a prepared tracer base.
  const PreparedTracer();

  /// Starts one prepared span.
  PreparedSpan startPreparedSpan(PreparedSpanStart start);

  /// Drains destination work.
  FutureOr<void> flush() {}

  /// Releases destination-owned resources.
  FutureOr<void> dispose() {}
}

/// Preliminary payload-free routing for a prepared log sink.
abstract interface class PreparedLogFilter {
  /// Whether this sink accepts a static event name and severity.
  bool allows(ObservabilityEventName name, LogLevel level);
}

/// Callback-backed preliminary prepared-log filter.
final class CallbackPreparedLogFilter implements PreparedLogFilter {
  /// Creates a filter from a payload-free callback.
  const CallbackPreparedLogFilter(this.callback);

  /// Filter callback.
  final bool Function(ObservabilityEventName name, LogLevel level) callback;

  @override
  bool allows(ObservabilityEventName name, LogLevel level) =>
      callback(name, level);
}

/// Callback-backed prepared log sink useful in tests and composition roots.
final class CallbackPreparedLogSink extends PreparedLogSink {
  /// Creates a callback-backed sink.
  const CallbackPreparedLogSink(this.onEvent, {this.onFlush, this.onDispose});

  /// Prepared event callback.
  final FutureOr<void> Function(PreparedLogEvent event) onEvent;

  /// Optional flush callback.
  final FutureOr<void> Function()? onFlush;

  /// Optional disposal callback.
  final FutureOr<void> Function()? onDispose;

  @override
  FutureOr<void> emitPrepared(PreparedLogEvent event) => onEvent(event);

  @override
  FutureOr<void> flush() => onFlush?.call();

  @override
  FutureOr<void> dispose() => onDispose?.call();
}

/// Callback-backed prepared error reporter.
final class CallbackPreparedErrorReporter extends PreparedErrorReporter {
  /// Creates a callback-backed reporter.
  const CallbackPreparedErrorReporter(
    this.onEvent, {
    this.onFlush,
    this.onDispose,
  });

  /// Prepared event callback.
  final FutureOr<void> Function(PreparedErrorEvent event) onEvent;

  /// Optional flush callback.
  final FutureOr<void> Function()? onFlush;

  /// Optional disposal callback.
  final FutureOr<void> Function()? onDispose;

  @override
  FutureOr<void> reportPrepared(PreparedErrorEvent event) => onEvent(event);

  @override
  FutureOr<void> flush() => onFlush?.call();

  @override
  FutureOr<void> dispose() => onDispose?.call();
}

/// Local `dart:developer` sink that cannot accept a raw [LogEvent].
final class PreparedDeveloperLogSink extends PreparedLogSink {
  /// Creates a local prepared developer sink.
  const PreparedDeveloperLogSink({this.name = 'dartitect'});

  /// Stable logger name.
  final String name;

  @override
  void emitPrepared(PreparedLogEvent event) {
    developer.log(
      event.message,
      name: name,
      level: _developerLevel(event.level),
      error: event.error,
      stackTrace: _preparedStackTrace(event.stackTrace),
      time: event.timestamp,
    );
  }

  static int _developerLevel(LogLevel level) => switch (level) {
    LogLevel.trace => 300,
    LogLevel.debug => 500,
    LogLevel.info => 800,
    LogLevel.warning => 900,
    LogLevel.error => 1000,
    LogLevel.fatal => 1200,
  };
}

/// Ownership declaration for one prepared log sink.
final class PreparedLogSinkRegistration {
  const PreparedLogSinkRegistration._(this.sink, this.isOwned, this.filter);

  /// Runtime-owned sink.
  const PreparedLogSinkRegistration.owned(
    PreparedLogSink sink, {
    PreparedLogFilter? filter,
  }) : this._(sink, true, filter);

  /// Borrowed sink that is flushed but never disposed.
  const PreparedLogSinkRegistration.borrowed(
    PreparedLogSink sink, {
    PreparedLogFilter? filter,
  }) : this._(sink, false, filter);

  /// Registered sink.
  final PreparedLogSink sink;

  /// Whether the runtime disposes the sink.
  final bool isOwned;

  /// Optional payload-free preliminary routing.
  final PreparedLogFilter? filter;
}

/// Ownership declaration for one prepared error reporter.
final class ErrorReporterRegistration {
  const ErrorReporterRegistration._(this.reporter, this.isOwned);

  /// Runtime-owned reporter.
  const ErrorReporterRegistration.owned(PreparedErrorReporter reporter)
    : this._(reporter, true);

  /// Borrowed reporter that is flushed but never disposed.
  const ErrorReporterRegistration.borrowed(PreparedErrorReporter reporter)
    : this._(reporter, false);

  /// Registered reporter.
  final PreparedErrorReporter reporter;

  /// Whether the runtime disposes the reporter.
  final bool isOwned;
}

/// Ownership declaration for one prepared tracer.
final class TracerRegistration {
  const TracerRegistration._(this.tracer, this.isOwned);

  /// Runtime-owned tracer.
  const TracerRegistration.owned(PreparedTracer tracer) : this._(tracer, true);

  /// Borrowed tracer that is flushed but never disposed.
  const TracerRegistration.borrowed(PreparedTracer tracer)
    : this._(tracer, false);

  /// Registered tracer.
  final PreparedTracer tracer;

  /// Whether the runtime disposes the tracer.
  final bool isOwned;
}

/// Validated local or remote prepared destination.
final class ObservabilityDestinationRegistration {
  ObservabilityDestinationRegistration._({
    required this.name,
    required this.kind,
    required Iterable<PreparedLogSinkRegistration> logSinks,
    required Iterable<ErrorReporterRegistration> errorReporters,
    required Iterable<TracerRegistration> tracers,
    required SamplingPolicy? samplingPolicy,
    required this.queueCapacity,
  }) : logSinks = List<PreparedLogSinkRegistration>.unmodifiable(logSinks),
       errorReporters = List<ErrorReporterRegistration>.unmodifiable(
         errorReporters,
       ),
       tracers = List<TracerRegistration>.unmodifiable(tracers),
       samplingPolicy = samplingPolicy ?? FixedSamplingPolicy() {
    _validateDestinationName(name);
    if (queueCapacity <= 0) {
      throw ArgumentError.value(queueCapacity, 'queueCapacity', 'must be > 0');
    }
    if (this.logSinks.isEmpty &&
        this.errorReporters.isEmpty &&
        this.tracers.isEmpty) {
      throw ArgumentError('Destination $name must declare a capability.');
    }
  }

  /// Creates a local destination.
  factory ObservabilityDestinationRegistration.local({
    String name = 'local',
    Iterable<PreparedLogSinkRegistration> logSinks =
        const <PreparedLogSinkRegistration>[],
    Iterable<ErrorReporterRegistration> errorReporters =
        const <ErrorReporterRegistration>[],
    Iterable<TracerRegistration> tracers = const <TracerRegistration>[],
    SamplingPolicy? samplingPolicy,
    int queueCapacity = 256,
  }) => ObservabilityDestinationRegistration._(
    name: name,
    kind: ObservabilityDestinationKind.local,
    logSinks: logSinks,
    errorReporters: errorReporters,
    tracers: tracers,
    samplingPolicy: samplingPolicy,
    queueCapacity: queueCapacity,
  );

  /// Creates a remote destination.
  factory ObservabilityDestinationRegistration.remote({
    required String name,
    Iterable<PreparedLogSinkRegistration> logSinks =
        const <PreparedLogSinkRegistration>[],
    Iterable<ErrorReporterRegistration> errorReporters =
        const <ErrorReporterRegistration>[],
    Iterable<TracerRegistration> tracers = const <TracerRegistration>[],
    SamplingPolicy? samplingPolicy,
    int queueCapacity = 128,
  }) => ObservabilityDestinationRegistration._(
    name: name,
    kind: ObservabilityDestinationKind.remote,
    logSinks: logSinks,
    errorReporters: errorReporters,
    tracers: tracers,
    samplingPolicy: samplingPolicy,
    queueCapacity: queueCapacity,
  );

  /// Stable low-cardinality name.
  final String name;

  /// Security boundary.
  final ObservabilityDestinationKind kind;

  /// Prepared log sinks.
  final List<PreparedLogSinkRegistration> logSinks;

  /// Prepared error reporters.
  final List<ErrorReporterRegistration> errorReporters;

  /// Prepared tracers.
  final List<TracerRegistration> tracers;

  /// Destination-local sampling state.
  final SamplingPolicy samplingPolicy;

  /// Maximum prepared events waiting for this destination.
  final int queueCapacity;

  /// Capabilities derived from the registered components.
  Set<ObservabilityDestinationCapability> get capabilities =>
      Set<ObservabilityDestinationCapability>.unmodifiable(
        <ObservabilityDestinationCapability>{
          if (logSinks.isNotEmpty) ObservabilityDestinationCapability.logs,
          if (errorReporters.isNotEmpty)
            ObservabilityDestinationCapability.errors,
          if (tracers.isNotEmpty) ObservabilityDestinationCapability.traces,
        },
      );
}

/// Immutable diagnostics for one named destination.
final class ObservabilityDestinationDiagnosticsSnapshot {
  /// Creates an immutable destination diagnostics snapshot.
  const ObservabilityDestinationDiagnosticsSnapshot({
    required this.name,
    required this.kind,
    required this.queueDepth,
    required this.maxQueueDepth,
    required this.enqueuedEvents,
    required this.dispatchedEvents,
    required this.droppedEvents,
    required this.sampledOutEvents,
    required this.filterFailures,
    required this.samplingFailures,
    required this.sinkFailures,
    required this.reporterFailures,
    required this.tracerFailures,
    required this.flushTimeouts,
    required this.sanitization,
  });

  /// Destination name.
  final String name;

  /// Destination security boundary.
  final ObservabilityDestinationKind kind;

  /// Prepared events currently queued.
  final int queueDepth;

  /// Highest observed queue depth.
  final int maxQueueDepth;

  /// Events accepted by the queue.
  final int enqueuedEvents;

  /// Events removed from the queue for dispatch.
  final int dispatchedEvents;

  /// Events rejected by queue capacity.
  final int droppedEvents;

  /// Log or span inputs removed by destination sampling.
  final int sampledOutEvents;

  /// Preliminary filter failures.
  final int filterFailures;

  /// Sampling policy failures.
  final int samplingFailures;

  /// Prepared sink failures.
  final int sinkFailures;

  /// Prepared reporter failures.
  final int reporterFailures;

  /// Prepared tracer failures.
  final int tracerFailures;

  /// Flushes that exceeded this destination's timeout.
  final int flushTimeouts;

  /// Aggregate payload-free sanitization counters.
  final ObservabilitySanitizationDiagnostics sanitization;
}

/// Immutable runtime diagnostics snapshot.
final class ObservabilityRuntimeDiagnosticsSnapshot {
  /// Creates an immutable runtime diagnostics snapshot.
  ObservabilityRuntimeDiagnosticsSnapshot({
    required this.messageBuilderFailures,
    required Map<String, ObservabilityDestinationDiagnosticsSnapshot>
    destinations,
  }) : destinations =
           Map<
             String,
             ObservabilityDestinationDiagnosticsSnapshot
           >.unmodifiable(destinations);

  /// Lazy message builders that failed.
  final int messageBuilderFailures;

  /// Per-destination snapshots keyed by validated name.
  final Map<String, ObservabilityDestinationDiagnosticsSnapshot> destinations;
}

/// Result of flushing one destination.
final class ObservabilityDestinationFlushResult {
  /// Creates one immutable destination outcome.
  const ObservabilityDestinationFlushResult({
    required this.name,
    required this.completed,
    required this.timedOut,
    required this.failureCount,
  });

  /// Destination name.
  final String name;

  /// Whether drain and component flush completed within the timeout.
  final bool completed;

  /// Whether the destination exceeded its timeout.
  final bool timedOut;

  /// Current isolated component failure count.
  final int failureCount;
}

/// Immutable per-destination flush result.
final class ObservabilityFlushResult {
  /// Creates an immutable aggregate flush result.
  ObservabilityFlushResult(
    Map<String, ObservabilityDestinationFlushResult> destinations,
  ) : destinations =
          Map<String, ObservabilityDestinationFlushResult>.unmodifiable(
            destinations,
          );

  /// Per-destination outcomes.
  final Map<String, ObservabilityDestinationFlushResult> destinations;

  /// Whether every destination completed within its timeout.
  bool get completed => destinations.values.every((value) => value.completed);
}

/// Destination-aware runtime whose queues retain prepared events only.
final class DestinationAwareObservabilityRuntime implements AsyncDisposable {
  /// Creates a validated privacy runtime.
  DestinationAwareObservabilityRuntime({
    required this.privacyPolicy,
    required Iterable<ObservabilityDestinationRegistration> destinations,
    Iterable<ObservabilityDataClassifier> classifiers =
        const <ObservabilityDataClassifier>[],
    Iterable<ObservabilityValueProjector> projectors =
        const <ObservabilityValueProjector>[],
    ObservabilitySanitizationLimits limits =
        const ObservabilitySanitizationLimits(),
    DateTime Function()? clock,
  }) : destinations = List<ObservabilityDestinationRegistration>.unmodifiable(
         destinations,
       ),
       _clock = clock ?? DateTime.now {
    _validateComposition(this.destinations);
    _states = <_DestinationState>[
      for (final destination in this.destinations)
        _DestinationState(
          registration: destination,
          sanitizer: ObservabilitySanitizer(
            policy: privacyPolicy,
            classifiers: classifiers,
            projectors: projectors,
            limits: limits,
          ),
        ),
    ];
    logger = _PrivacyLogger(this);
    reporter = _PrivacyReporter(this);
    tracing = _PrivacyTracer(this);
  }

  /// Privacy policy shared by all destination-specific sanitizers.
  final ObservabilityPrivacyPolicy privacyPolicy;

  /// Immutable destination composition.
  final List<ObservabilityDestinationRegistration> destinations;

  final DateTime Function() _clock;
  late final List<_DestinationState> _states;

  /// Runtime-local logger.
  late final DartitectLogger logger;

  /// Runtime-local prepared error reporter.
  late final ErrorReporter reporter;

  /// Runtime-local prepared tracer.
  late final Tracer tracing;

  var _messageBuilderFailures = 0;
  var _accepting = true;
  var _disposed = false;
  Future<void>? _disposal;

  /// Whether disposal completed.
  bool get isDisposed => _disposed;

  /// Returns a fresh immutable diagnostics snapshot.
  ObservabilityRuntimeDiagnosticsSnapshot get diagnostics =>
      ObservabilityRuntimeDiagnosticsSnapshot(
        messageBuilderFailures: _messageBuilderFailures,
        destinations: <String, ObservabilityDestinationDiagnosticsSnapshot>{
          for (final state in _states)
            state.registration.name: state.snapshot(),
        },
      );

  void _event(ObservabilityLogEvent input) {
    if (!_accepting) return;
    final timestamp = _clock().toUtc();
    final candidates = <_LogCandidate>[];
    for (final state in _states) {
      final targets = state.logTargets(input.name, input.level);
      if (targets.isEmpty) continue;
      final probe = LogEvent(
        timestamp: timestamp,
        name: input.name,
        level: input.level,
        message: '',
        context: ObservabilityContext(
          traceContext: _copyTraceContext(input.context?.traceContext),
        ),
      );
      try {
        if (!state.registration.samplingPolicy.shouldSampleLog(probe)) {
          state.sampledOutEvents += 1;
          continue;
        }
      } on Object {
        state.samplingFailures += 1;
        continue;
      }
      candidates.add(_LogCandidate(state, targets));
    }
    if (candidates.isEmpty) return;
    final String message;
    try {
      message = input.message();
    } on Object {
      _messageBuilderFailures += 1;
      return;
    }
    for (final candidate in candidates) {
      final state = candidate.state;
      final preparedMessage = state.sanitize(
        message,
        classes: <ObservabilityDataClass>{ObservabilityDataClass.errorMessage},
      );
      final preparedContext = state.prepareContext(input.context);
      final preparedError = input.error == null
          ? null
          : state.sanitizeError(input.error!);
      final preparedStack = input.stackTrace == null
          ? null
          : state.sanitizeStack(input.stackTrace!);
      state.enqueue(
        _PreparedLogDispatch(
          PreparedLogEvent._(
            timestamp: timestamp,
            name: input.name,
            level: input.level,
            message: _preparedString(preparedMessage),
            context: preparedContext,
            error: preparedError,
            stackTrace: preparedStack,
          ),
          candidate.targets,
        ),
      );
    }
  }

  void _report(ErrorEvent input) {
    if (!_accepting) return;
    for (final state in _states) {
      if (state.registration.errorReporters.isEmpty) continue;
      final fingerprint = <String>[];
      for (final value in input.fingerprint) {
        fingerprint.add(
          _preparedString(
            state.sanitize(
              value,
              classes: <ObservabilityDataClass>{
                ObservabilityDataClass.errorFingerprint,
              },
            ),
          ),
        );
      }
      state.enqueue(
        _PreparedErrorDispatch(
          PreparedErrorEvent._(
            timestamp: input.timestamp.toUtc(),
            error: state.sanitizeError(input.error),
            stackTrace: state.sanitizeStack(input.stackTrace),
            severity: input.severity,
            mechanism: input.mechanism,
            handled: input.handled,
            fingerprint: List<String>.unmodifiable(fingerprint),
            context: state.prepareContext(input.context),
          ),
        ),
      );
    }
  }

  Span _startSpan(
    String name, {
    required TraceContext? parent,
    required SpanKind kind,
    required Map<String, Object?> attributes,
  }) {
    if (!_accepting) {
      return NoOpTracer().startSpan('[DISPOSED]', parent: parent, kind: kind);
    }
    final bindings = <_PreparedSpanBinding>[];
    for (final state in _states) {
      if (state.registration.tracers.isEmpty) continue;
      final preparedName = _preparedString(
        state.sanitize(
          name,
          classes: <ObservabilityDataClass>{
            ObservabilityDataClass.safeMetadata,
          },
        ),
      );
      try {
        if (!state.registration.samplingPolicy.shouldSampleSpan(preparedName)) {
          state.sampledOutEvents += 1;
          continue;
        }
      } on Object {
        state.samplingFailures += 1;
        continue;
      }
      final start = PreparedSpanStart._(
        name: preparedName,
        parent: _copyTraceContext(parent),
        kind: kind,
        attributes: state.prepareAttributes(attributes),
      );
      for (final registration in state.registration.tracers) {
        try {
          bindings.add(
            _PreparedSpanBinding(
              state,
              registration.tracer.startPreparedSpan(start),
            ),
          );
        } on Object {
          state.tracerFailures += 1;
        }
      }
    }
    if (bindings.isEmpty) {
      return NoOpTracer().startSpan(
        '[SAMPLED_OUT]',
        parent: parent,
        kind: kind,
      );
    }
    return _CompositePreparedSpan(bindings);
  }

  /// Flushes every destination concurrently with an independent timeout.
  Future<ObservabilityFlushResult> flushDetailed([
    Duration timeout = const Duration(seconds: 5),
  ]) async {
    final results = await Future.wait(
      <Future<ObservabilityDestinationFlushResult>>[
        for (final state in _states) state.flush(timeout),
      ],
    );
    return ObservabilityFlushResult(
      <String, ObservabilityDestinationFlushResult>{
        for (final result in results) result.name: result,
      },
    );
  }

  /// Compatibility flush that reports whether every destination completed.
  Future<bool> flush(Duration timeout) async =>
      (await flushDetailed(timeout)).completed;

  /// Idempotently stops intake, flushes, and disposes owned components.
  @override
  Future<void> disposeAsync() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _accepting = false;
    await flush(const Duration(seconds: 5));
    await Future.wait(<Future<void>>[
      for (final state in _states) state.dispose(),
    ]);
    _disposed = true;
  }
}

final class _PrivacyLogger extends DartitectLogger {
  const _PrivacyLogger(this.runtime);

  final DestinationAwareObservabilityRuntime runtime;

  @override
  void event(ObservabilityLogEvent event) => runtime._event(event);

  @override
  void log(
    LogLevel level,
    String message, {
    ObservabilityContext? context,
    Object? error,
    StackTrace? stackTrace,
  }) => runtime._event(
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

final class _PrivacyReporter extends ErrorReporter {
  const _PrivacyReporter(this.runtime);

  final DestinationAwareObservabilityRuntime runtime;

  @override
  void report(ErrorEvent event) => runtime._report(event);
}

final class _PrivacyTracer extends Tracer {
  const _PrivacyTracer(this.runtime);

  final DestinationAwareObservabilityRuntime runtime;

  @override
  Span startSpan(
    String name, {
    TraceContext? parent,
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) => runtime._startSpan(
    name,
    parent: parent,
    kind: kind,
    attributes: attributes,
  );
}

final class _CompositePreparedSpan extends Span {
  _CompositePreparedSpan(this.bindings) : context = bindings.first.span.context;

  final List<_PreparedSpanBinding> bindings;

  @override
  final TraceContext context;

  var _ended = false;

  @override
  bool get isEnded => _ended;

  @override
  void setAttribute(String key, Object? value) {
    if (_ended) return;
    for (final binding in bindings) {
      final attributes = binding.state.prepareAttributes(<String, Object?>{
        key: value,
      });
      if (attributes.isEmpty) continue;
      final entry = attributes.entries.first;
      try {
        binding.span.setPreparedAttribute(
          PreparedSpanAttribute._(entry.key, entry.value),
        );
      } on Object {
        binding.state.tracerFailures += 1;
      }
    }
  }

  @override
  void addEvent(
    String name, {
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {
    if (_ended) return;
    for (final binding in bindings) {
      try {
        binding.span.addPreparedEvent(
          PreparedSpanEvent._(
            name: _preparedString(
              binding.state.sanitize(
                name,
                classes: <ObservabilityDataClass>{
                  ObservabilityDataClass.safeMetadata,
                },
              ),
            ),
            attributes: binding.state.prepareAttributes(attributes),
          ),
        );
      } on Object {
        binding.state.tracerFailures += 1;
      }
    }
  }

  @override
  Future<void> end({
    SpanStatus status = SpanStatus.unset,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    if (_ended) return;
    _ended = true;
    await Future.wait(<Future<void>>[
      for (final binding in bindings)
        _endBinding(
          binding,
          status: status,
          error: error,
          stackTrace: stackTrace,
        ),
    ]);
  }

  static Future<void> _endBinding(
    _PreparedSpanBinding binding, {
    required SpanStatus status,
    required Object? error,
    required StackTrace? stackTrace,
  }) async {
    try {
      await binding.span.endPrepared(
        PreparedSpanEnd._(
          status: status,
          error: error == null ? null : binding.state.sanitizeError(error),
          stackTrace: stackTrace == null
              ? null
              : binding.state.sanitizeStack(stackTrace),
        ),
      );
    } on Object {
      binding.state.tracerFailures += 1;
    }
  }
}

final class _PreparedSpanBinding {
  const _PreparedSpanBinding(this.state, this.span);

  final _DestinationState state;
  final PreparedSpan span;
}

final class _DestinationState {
  _DestinationState({required this.registration, required this.sanitizer});

  final ObservabilityDestinationRegistration registration;
  final ObservabilitySanitizer sanitizer;
  final Queue<_PreparedDispatch> queue = Queue<_PreparedDispatch>();

  Completer<void>? _idle;
  var _draining = false;
  var _accepting = true;

  int maxQueueDepth = 0;
  int enqueuedEvents = 0;
  int dispatchedEvents = 0;
  int droppedEvents = 0;
  int sampledOutEvents = 0;
  int filterFailures = 0;
  int samplingFailures = 0;
  int sinkFailures = 0;
  int reporterFailures = 0;
  int tracerFailures = 0;
  int flushTimeouts = 0;
  final _SanitizationAccumulator sanitization = _SanitizationAccumulator();

  List<int> logTargets(ObservabilityEventName name, LogLevel level) {
    final output = <int>[];
    for (var index = 0; index < registration.logSinks.length; index += 1) {
      final filter = registration.logSinks[index].filter;
      try {
        if (filter == null || filter.allows(name, level)) output.add(index);
      } on Object {
        filterFailures += 1;
      }
    }
    return List<int>.unmodifiable(output);
  }

  Object? sanitize(
    Object? value, {
    Set<ObservabilityDataClass> classes = const <ObservabilityDataClass>{},
  }) {
    final result = sanitizer.prepare(
      value,
      destination: registration.kind,
      destinationName: registration.name,
      classes: classes,
    );
    sanitization.add(result.diagnostics);
    return result.value;
  }

  Object sanitizeError(Object error) {
    final result = sanitizer.prepareError(
      error,
      destination: registration.kind,
      destinationName: registration.name,
    );
    sanitization.add(result.diagnostics);
    return result.value ?? '[DENIED]';
  }

  Object sanitizeStack(Object stackTrace) {
    final result = sanitizer.prepareStackTrace(
      stackTrace,
      destination: registration.kind,
      destinationName: registration.name,
    );
    sanitization.add(result.diagnostics);
    return result.value ?? '[DENIED]';
  }

  PreparedObservabilityContext prepareContext(ObservabilityContext? context) =>
      PreparedObservabilityContext._(
        traceContext: _copyTraceContext(context?.traceContext),
        attributes: prepareAttributes(
          context?.attributes ?? const <String, Object?>{},
        ),
      );

  Map<String, Object?> prepareAttributes(Map<String, Object?> input) {
    final result = sanitizer.prepare(
      ObservabilityClassifiedValue<Object?>(
        input,
        classes: <ObservabilityDataClass>{ObservabilityDataClass.safeMetadata},
      ),
      destination: registration.kind,
      destinationName: registration.name,
    );
    sanitization.add(result.diagnostics);
    return switch (result.value) {
      final Map<String, Object?> value => value,
      _ => const <String, Object?>{},
    };
  }

  void enqueue(_PreparedDispatch dispatch) {
    if (!_accepting) return;
    if (queue.length >= registration.queueCapacity) {
      droppedEvents += 1;
      return;
    }
    queue.add(dispatch);
    enqueuedEvents += 1;
    if (queue.length > maxQueueDepth) maxQueueDepth = queue.length;
    _idle ??= Completer<void>();
    if (!_draining) {
      _draining = true;
      scheduleMicrotask(_drain);
    }
  }

  Future<void> _drain() async {
    while (queue.isNotEmpty) {
      final dispatch = queue.removeFirst();
      dispatchedEvents += 1;
      switch (dispatch) {
        case _PreparedLogDispatch(:final event, :final targets):
          for (final index in targets) {
            try {
              await registration.logSinks[index].sink.emitPrepared(event);
            } on Object {
              sinkFailures += 1;
            }
          }
        case _PreparedErrorDispatch(:final event):
          for (final reporter in registration.errorReporters) {
            try {
              await reporter.reporter.reportPrepared(event);
            } on Object {
              reporterFailures += 1;
            }
          }
      }
    }
    _draining = false;
    _idle?.complete();
    _idle = null;
    if (queue.isNotEmpty && !_draining) {
      _draining = true;
      scheduleMicrotask(_drain);
    }
  }

  Future<ObservabilityDestinationFlushResult> flush(Duration timeout) async {
    Future<void> operation() async {
      await (_idle?.future ?? Future<void>.value());
      for (final sink in registration.logSinks) {
        try {
          await sink.sink.flush();
        } on Object {
          sinkFailures += 1;
        }
      }
      for (final reporter in registration.errorReporters) {
        try {
          await reporter.reporter.flush();
        } on Object {
          reporterFailures += 1;
        }
      }
      for (final tracer in registration.tracers) {
        try {
          await tracer.tracer.flush();
        } on Object {
          tracerFailures += 1;
        }
      }
    }

    try {
      await operation().timeout(timeout);
      return ObservabilityDestinationFlushResult(
        name: registration.name,
        completed: true,
        timedOut: false,
        failureCount: failureCount,
      );
    } on TimeoutException {
      flushTimeouts += 1;
      return ObservabilityDestinationFlushResult(
        name: registration.name,
        completed: false,
        timedOut: true,
        failureCount: failureCount,
      );
    }
  }

  int get failureCount =>
      filterFailures +
      samplingFailures +
      sinkFailures +
      reporterFailures +
      tracerFailures;

  Future<void> dispose() async {
    _accepting = false;
    for (final tracer in registration.tracers.reversed) {
      if (!tracer.isOwned) continue;
      try {
        await tracer.tracer.dispose();
      } on Object {
        tracerFailures += 1;
      }
    }
    for (final reporter in registration.errorReporters.reversed) {
      if (!reporter.isOwned) continue;
      try {
        await reporter.reporter.dispose();
      } on Object {
        reporterFailures += 1;
      }
    }
    for (final sink in registration.logSinks.reversed) {
      if (!sink.isOwned) continue;
      try {
        await sink.sink.dispose();
      } on Object {
        sinkFailures += 1;
      }
    }
  }

  ObservabilityDestinationDiagnosticsSnapshot snapshot() =>
      ObservabilityDestinationDiagnosticsSnapshot(
        name: registration.name,
        kind: registration.kind,
        queueDepth: queue.length,
        maxQueueDepth: maxQueueDepth,
        enqueuedEvents: enqueuedEvents,
        dispatchedEvents: dispatchedEvents,
        droppedEvents: droppedEvents,
        sampledOutEvents: sampledOutEvents,
        filterFailures: filterFailures,
        samplingFailures: samplingFailures,
        sinkFailures: sinkFailures,
        reporterFailures: reporterFailures,
        tracerFailures: tracerFailures,
        flushTimeouts: flushTimeouts,
        sanitization: sanitization.snapshot(),
      );
}

sealed class _PreparedDispatch {
  const _PreparedDispatch();
}

final class _PreparedLogDispatch extends _PreparedDispatch {
  const _PreparedLogDispatch(this.event, this.targets);

  final PreparedLogEvent event;
  final List<int> targets;
}

final class _PreparedErrorDispatch extends _PreparedDispatch {
  const _PreparedErrorDispatch(this.event);

  final PreparedErrorEvent event;
}

final class _LogCandidate {
  const _LogCandidate(this.state, this.targets);

  final _DestinationState state;
  final List<int> targets;
}

final class _SanitizationAccumulator {
  int visitedNodes = 0;
  int textCodePoints = 0;
  int stackFrames = 0;
  int classificationWork = 0;
  int deniedValues = 0;
  int maskedValues = 0;
  int allowedValues = 0;
  int unknownObjects = 0;
  int cycles = 0;
  int truncatedNodes = 0;
  int truncatedText = 0;
  int truncatedCollections = 0;
  int truncatedFrames = 0;
  int truncatedClassification = 0;
  int classifierFailures = 0;
  int projectorFailures = 0;

  void add(ObservabilitySanitizationDiagnostics value) {
    visitedNodes += value.visitedNodes;
    textCodePoints += value.textCodePoints;
    stackFrames += value.stackFrames;
    classificationWork += value.classificationWork;
    deniedValues += value.deniedValues;
    maskedValues += value.maskedValues;
    allowedValues += value.allowedValues;
    unknownObjects += value.unknownObjects;
    cycles += value.cycles;
    truncatedNodes += value.truncatedNodes;
    truncatedText += value.truncatedText;
    truncatedCollections += value.truncatedCollections;
    truncatedFrames += value.truncatedFrames;
    truncatedClassification += value.truncatedClassification;
    classifierFailures += value.classifierFailures;
    projectorFailures += value.projectorFailures;
  }

  ObservabilitySanitizationDiagnostics snapshot() =>
      ObservabilitySanitizationDiagnostics.withActionCounts(
        visitedNodes: visitedNodes,
        textCodePoints: textCodePoints,
        stackFrames: stackFrames,
        classificationWork: classificationWork,
        deniedValues: deniedValues,
        maskedValues: maskedValues,
        allowedValues: allowedValues,
        unknownObjects: unknownObjects,
        cycles: cycles,
        truncatedNodes: truncatedNodes,
        truncatedText: truncatedText,
        truncatedCollections: truncatedCollections,
        truncatedFrames: truncatedFrames,
        truncatedClassification: truncatedClassification,
        classifierFailures: classifierFailures,
        projectorFailures: projectorFailures,
      );
}

TraceContext? _copyTraceContext(TraceContext? context) => context == null
    ? null
    : TraceContext(
        traceId: context.traceId,
        spanId: context.spanId,
        traceFlags: context.traceFlags,
        traceState: context.traceState,
      );

String _preparedString(Object? value) =>
    value is String ? value : '[INVALID_PREPARED_TEXT]';

StackTrace? _preparedStackTrace(Object? value) => switch (value) {
  final List<String> frames => StackTrace.fromString(frames.join('\n')),
  final String marker => StackTrace.fromString(marker),
  _ => null,
};

void _validateComposition(
  List<ObservabilityDestinationRegistration> destinations,
) {
  if (destinations.isEmpty) {
    throw ArgumentError.value(
      destinations,
      'destinations',
      'must not be empty',
    );
  }
  final names = <String>{};
  final components = HashMap<Object, bool>.identity();
  final samplers = HashSet<SamplingPolicy>.identity();
  for (final destination in destinations) {
    if (!names.add(destination.name)) {
      throw ArgumentError.value(
        destination.name,
        'destinations',
        'contains a duplicate name',
      );
    }
    if (!samplers.add(destination.samplingPolicy)) {
      throw ArgumentError(
        'Each destination must own independent sampling policy state.',
      );
    }
    for (final component in <(Object, bool)>[
      for (final sink in destination.logSinks) (sink.sink, sink.isOwned),
      for (final reporter in destination.errorReporters)
        (reporter.reporter, reporter.isOwned),
      for (final tracer in destination.tracers) (tracer.tracer, tracer.isOwned),
    ]) {
      final previousOwnership = components[component.$1];
      if (previousOwnership != null) {
        final detail = previousOwnership == component.$2
            ? 'duplicate component instance'
            : 'conflicting component ownership';
        throw ArgumentError('Destination composition contains a $detail.');
      }
      components[component.$1] = component.$2;
    }
  }
}

void _validateDestinationName(String name) {
  if (!RegExp(r'^[a-z][a-z0-9_-]{1,39}$').hasMatch(name)) {
    throw ArgumentError.value(
      name,
      'name',
      'must be 2-40 lowercase ASCII characters',
    );
  }
}
