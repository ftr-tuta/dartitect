import 'dart:async';
import 'dart:collection';

import 'package:dartitect_observability/dartitect_observability.dart';

/// One expected privacy decision exercised by
/// [ObservabilityPrivacyPolicyHarness].
final class ObservabilityPrivacyExpectation {
  /// Creates one destination-aware expectation.
  ObservabilityPrivacyExpectation({
    required this.destination,
    required Iterable<ObservabilityDataClass> classes,
    required this.action,
    this.destinationName,
    this.source,
  }) : classes = Set<ObservabilityDataClass>.unmodifiable(classes) {
    if (this.classes.isEmpty) {
      throw ArgumentError.value(classes, 'classes', 'must not be empty');
    }
  }

  /// Destination security boundary.
  final ObservabilityDestinationKind destination;

  /// Optional validated destination name.
  final String? destinationName;

  /// Independently resolved classifications.
  final Set<ObservabilityDataClass> classes;

  /// Expected effective action.
  final ObservabilityPrivacyAction action;

  /// Optional expected rule source.
  final ObservabilityPrivacyDecisionSource? source;
}

/// Framework-neutral assertions for one reviewed privacy policy.
final class ObservabilityPrivacyPolicyHarness {
  /// Creates a harness around [policy].
  const ObservabilityPrivacyPolicyHarness(this.policy);

  /// Policy under test.
  final ObservabilityPrivacyPolicy policy;

  /// Verifies a local, remote, or named-destination matrix.
  void verify(Iterable<ObservabilityPrivacyExpectation> expectations) {
    for (final expectation in expectations) {
      final decision = policy.explain(
        destination: expectation.destination,
        destinationName: expectation.destinationName,
        classes: expectation.classes,
      );
      if (decision.action != expectation.action ||
          expectation.source != null && decision.source != expectation.source) {
        throw StateError(
          'Privacy matrix mismatch for ${expectation.destination.name}/'
          '${expectation.destinationName ?? '<unnamed>'}: expected '
          '${expectation.action.name}/${expectation.source?.name ?? '*'}, got '
          '${decision.action.name}/${decision.source.name}.',
        );
      }
    }
  }

  /// Verifies the invariant `deny > mask > allow` for three classes whose
  /// individual decisions are known to be deny, mask, and allow.
  void verifyRestrictivePrecedence({
    required ObservabilityDestinationKind destination,
    required ObservabilityDataClass denied,
    required ObservabilityDataClass masked,
    required ObservabilityDataClass allowed,
    String? destinationName,
  }) {
    ObservabilityPrivacyAction decide(Set<ObservabilityDataClass> classes) =>
        policy
            .explain(
              destination: destination,
              destinationName: destinationName,
              classes: classes,
            )
            .action;

    final singles = <ObservabilityDataClass, ObservabilityPrivacyAction>{
      denied: ObservabilityPrivacyAction.deny,
      masked: ObservabilityPrivacyAction.mask,
      allowed: ObservabilityPrivacyAction.allow,
    };
    for (final entry in singles.entries) {
      final actual = decide(<ObservabilityDataClass>{entry.key});
      if (actual != entry.value) {
        throw StateError(
          '${entry.key.wireName} must resolve to ${entry.value.name}, '
          'not ${actual.name}.',
        );
      }
    }
    if (decide(<ObservabilityDataClass>{allowed, masked}) !=
        ObservabilityPrivacyAction.mask) {
      throw StateError('Mask must win over allow.');
    }
    if (decide(<ObservabilityDataClass>{allowed, masked, denied}) !=
        ObservabilityPrivacyAction.deny) {
      throw StateError('Deny must win over mask and allow.');
    }
  }
}

/// Deterministic structural-budget gate for sanitizer tests.
final class ObservabilitySanitizationBudgetHarness {
  /// Creates a gate around one configured [sanitizer].
  const ObservabilitySanitizationBudgetHarness(this.sanitizer);

  /// Sanitizer whose configured global budgets are enforced.
  final ObservabilitySanitizer sanitizer;

  /// Prepares [value] and fails if any deterministic global budget is crossed.
  PreparedObservabilityValue prepareAndVerify(
    Object? value, {
    required ObservabilityDestinationKind destination,
    String? destinationName,
    String? key,
    Set<ObservabilityDataClass> classes = const <ObservabilityDataClass>{},
  }) {
    final prepared = sanitizer.prepare(
      value,
      destination: destination,
      destinationName: destinationName,
      key: key,
      classes: classes,
    );
    verify(prepared);
    return prepared;
  }

  /// Verifies node, text, frame, classification, depth, and collection bounds.
  void verify(PreparedObservabilityValue prepared) {
    final diagnostics = prepared.diagnostics;
    final limits = sanitizer.limits;
    final failures = <String>[
      if (diagnostics.visitedNodes > limits.maxNodes)
        'nodes ${diagnostics.visitedNodes}/${limits.maxNodes}',
      if (diagnostics.textCodePoints > limits.maxTotalTextCodePoints)
        'text ${diagnostics.textCodePoints}/${limits.maxTotalTextCodePoints}',
      if (diagnostics.stackFrames > limits.maxStackFrames)
        'frames ${diagnostics.stackFrames}/${limits.maxStackFrames}',
      if (diagnostics.classificationWork > limits.maxClassificationWork)
        'classification ${diagnostics.classificationWork}/${limits.maxClassificationWork}',
      ..._structuralFailures(prepared.value, limits),
    ];
    if (failures.isNotEmpty) {
      throw StateError('Sanitization budget exceeded: ${failures.join(', ')}.');
    }
  }
}

/// Prepared-only in-memory destination for privacy, queue, and ownership tests.
final class RecordingObservabilityDestination {
  /// Creates a local or remote destination probe.
  RecordingObservabilityDestination({
    required this.name,
    required this.kind,
    this.logGate,
    this.failLogs = false,
    this.failErrors = false,
    this.failTraces = false,
  }) {
    logSink = _RecordingPreparedLogSink(this);
    errorReporter = _RecordingPreparedErrorReporter(this);
    tracer = _RecordingPreparedTracer(this);
  }

  /// Stable destination name.
  final String name;

  /// Destination security boundary.
  final ObservabilityDestinationKind kind;

  /// Optional gate used to model a slow log destination.
  final Future<void>? logGate;

  /// Whether log delivery fails after recording the prepared event.
  final bool failLogs;

  /// Whether error delivery fails after recording the prepared event.
  final bool failErrors;

  /// Whether starting a prepared span fails.
  final bool failTraces;

  /// Prepared logs in delivery order.
  final List<PreparedLogEvent> logs = <PreparedLogEvent>[];

  /// Prepared errors in delivery order.
  final List<PreparedErrorEvent> errors = <PreparedErrorEvent>[];

  /// Prepared span starts in creation order.
  final List<PreparedSpanStart> spanStarts = <PreparedSpanStart>[];

  /// Prepared spans created by [tracer].
  final List<RecordingPreparedSpan> spans = <RecordingPreparedSpan>[];

  /// Prepared-only log sink instance, useful for conflict tests.
  late final PreparedLogSink logSink;

  /// Prepared-only error reporter instance, useful for conflict tests.
  late final PreparedErrorReporter errorReporter;

  /// Prepared-only tracer instance, useful for conflict tests.
  late final PreparedTracer tracer;

  /// Component flush calls.
  int flushCalls = 0;

  /// Owned component dispose calls.
  int disposeCalls = 0;

  var _nextId = 1;

  /// Builds a validated registration from the prepared-only components.
  ObservabilityDestinationRegistration registration({
    bool owned = false,
    bool includeLogs = true,
    bool includeErrors = true,
    bool includeTraces = true,
    int queueCapacity = 256,
    SamplingPolicy? samplingPolicy,
  }) {
    final logRegistration = owned
        ? PreparedLogSinkRegistration.owned(logSink)
        : PreparedLogSinkRegistration.borrowed(logSink);
    final errorRegistration = owned
        ? ErrorReporterRegistration.owned(errorReporter)
        : ErrorReporterRegistration.borrowed(errorReporter);
    final tracerRegistration = owned
        ? TracerRegistration.owned(tracer)
        : TracerRegistration.borrowed(tracer);
    return switch (kind) {
      ObservabilityDestinationKind.local =>
        ObservabilityDestinationRegistration.local(
          name: name,
          logSinks: includeLogs
              ? <PreparedLogSinkRegistration>[logRegistration]
              : const <PreparedLogSinkRegistration>[],
          errorReporters: includeErrors
              ? <ErrorReporterRegistration>[errorRegistration]
              : const <ErrorReporterRegistration>[],
          tracers: includeTraces
              ? <TracerRegistration>[tracerRegistration]
              : const <TracerRegistration>[],
          queueCapacity: queueCapacity,
          samplingPolicy: samplingPolicy,
        ),
      ObservabilityDestinationKind.remote =>
        ObservabilityDestinationRegistration.remote(
          name: name,
          logSinks: includeLogs
              ? <PreparedLogSinkRegistration>[logRegistration]
              : const <PreparedLogSinkRegistration>[],
          errorReporters: includeErrors
              ? <ErrorReporterRegistration>[errorRegistration]
              : const <ErrorReporterRegistration>[],
          tracers: includeTraces
              ? <TracerRegistration>[tracerRegistration]
              : const <TracerRegistration>[],
          queueCapacity: queueCapacity,
          samplingPolicy: samplingPolicy,
        ),
    };
  }

  TraceContext _nextContext() {
    final trace = _nextId++;
    final span = _nextId++;
    return TraceContext(
      traceId: trace.toRadixString(16).padLeft(32, '0'),
      spanId: span.toRadixString(16).padLeft(16, '0'),
      traceFlags: '01',
    );
  }
}

/// One prepared span recorded without access to any raw runtime input.
final class RecordingPreparedSpan extends PreparedSpan {
  /// Creates a span from a prepared start and deterministic [context].
  RecordingPreparedSpan({required this.start, required this.context})
    : attributes = <String, Object?>{...start.attributes};

  /// Prepared start received by the destination.
  final PreparedSpanStart start;

  /// Attributes accepted after start.
  final Map<String, Object?> attributes;

  /// Prepared events in delivery order.
  final List<PreparedSpanEvent> events = <PreparedSpanEvent>[];

  /// Prepared terminal input, if ended.
  PreparedSpanEnd? end;

  @override
  final TraceContext context;

  @override
  bool get isEnded => end != null;

  @override
  void addPreparedEvent(PreparedSpanEvent event) {
    if (!isEnded) events.add(event);
  }

  @override
  void setPreparedAttribute(PreparedSpanAttribute attribute) {
    if (!isEnded) attributes[attribute.key] = attribute.value;
  }

  @override
  void endPrepared(PreparedSpanEnd end) {
    this.end ??= end;
  }
}

/// Fails when a sentinel appears in prepared observability evidence.
///
/// The traversal recognizes only closed prepared/JSON-like structures and
/// never calls `toString()` on arbitrary objects.
void expectNoSensitiveObservabilityData(
  Object? evidence, {
  required Iterable<String> sentinels,
}) {
  final checked = sentinels.toList(growable: false);
  if (checked.isEmpty || checked.any((sentinel) => sentinel.isEmpty)) {
    throw ArgumentError.value(
      sentinels,
      'sentinels',
      'must contain non-empty values',
    );
  }
  final visited = HashSet<Object>.identity();
  for (final fragment in _evidenceFragments(evidence, visited)) {
    for (final sentinel in checked) {
      if (fragment.contains(sentinel)) {
        throw StateError('Sensitive observability sentinel found: $sentinel.');
      }
    }
  }
}

final class _RecordingPreparedLogSink extends PreparedLogSink {
  const _RecordingPreparedLogSink(this.owner);

  final RecordingObservabilityDestination owner;

  @override
  Future<void> emitPrepared(PreparedLogEvent event) async {
    owner.logs.add(event);
    if (owner.logGate case final gate?) await gate;
    if (owner.failLogs) throw const _DestinationFailure();
  }

  @override
  void flush() => owner.flushCalls += 1;

  @override
  void dispose() => owner.disposeCalls += 1;
}

final class _RecordingPreparedErrorReporter extends PreparedErrorReporter {
  const _RecordingPreparedErrorReporter(this.owner);

  final RecordingObservabilityDestination owner;

  @override
  void reportPrepared(PreparedErrorEvent event) {
    owner.errors.add(event);
    if (owner.failErrors) throw const _DestinationFailure();
  }

  @override
  void flush() => owner.flushCalls += 1;

  @override
  void dispose() => owner.disposeCalls += 1;
}

final class _RecordingPreparedTracer extends PreparedTracer {
  const _RecordingPreparedTracer(this.owner);

  final RecordingObservabilityDestination owner;

  @override
  PreparedSpan startPreparedSpan(PreparedSpanStart start) {
    if (owner.failTraces) throw const _DestinationFailure();
    final span = RecordingPreparedSpan(
      start: start,
      context: owner._nextContext(),
    );
    owner.spanStarts.add(start);
    owner.spans.add(span);
    return span;
  }

  @override
  void flush() => owner.flushCalls += 1;

  @override
  void dispose() => owner.disposeCalls += 1;
}

final class _DestinationFailure implements Exception {
  const _DestinationFailure();
}

List<String> _structuralFailures(
  Object? value,
  ObservabilitySanitizationLimits limits,
) {
  final failures = <String>[];
  void visit(Object? current, int depth) {
    if (current is Map<String, Object?>) {
      if (depth > limits.maxDepth) failures.add('depth $depth');
      if (current.length > limits.maxCollectionLength + 1) {
        failures.add('map length ${current.length}');
      }
      for (final entry in current.entries) {
        visit(entry.value, depth + 1);
      }
    } else if (current is List<Object?>) {
      if (depth > limits.maxDepth) failures.add('depth $depth');
      if (current.length > limits.maxCollectionLength + 1) {
        failures.add('list length ${current.length}');
      }
      for (final item in current) {
        visit(item, depth + 1);
      }
    }
  }

  visit(value, 0);
  return failures;
}

Iterable<String> _evidenceFragments(Object? value, Set<Object> visited) sync* {
  if (value == null || value is num || value is bool || value is DateTime) {
    return;
  }
  if (value is String) {
    yield value;
    return;
  }
  if (value is ObservabilityEventName) {
    yield value.value;
    return;
  }
  if (value is TraceContext) {
    yield value.traceId;
    yield value.spanId;
    yield value.traceFlags;
    if (value.traceState case final state?) yield state;
    return;
  }
  if (value is PreparedObservabilityContext) {
    yield* _evidenceFragments(value.traceContext, visited);
    yield* _evidenceFragments(value.attributes, visited);
    return;
  }
  if (value is PreparedLogEvent) {
    yield* _evidenceFragments(value.name, visited);
    yield value.message;
    yield* _evidenceFragments(value.context, visited);
    yield* _evidenceFragments(value.error, visited);
    yield* _evidenceFragments(value.stackTrace, visited);
    return;
  }
  if (value is PreparedErrorEvent) {
    yield* _evidenceFragments(value.error, visited);
    yield* _evidenceFragments(value.stackTrace, visited);
    yield* _evidenceFragments(value.fingerprint, visited);
    yield* _evidenceFragments(value.context, visited);
    return;
  }
  if (value is PreparedSpanStart) {
    yield value.name;
    yield* _evidenceFragments(value.parent, visited);
    yield* _evidenceFragments(value.attributes, visited);
    return;
  }
  if (value is PreparedSpanAttribute) {
    yield value.key;
    yield* _evidenceFragments(value.value, visited);
    return;
  }
  if (value is PreparedSpanEvent) {
    yield value.name;
    yield* _evidenceFragments(value.attributes, visited);
    return;
  }
  if (value is PreparedSpanEnd) {
    yield* _evidenceFragments(value.error, visited);
    yield* _evidenceFragments(value.stackTrace, visited);
    return;
  }
  if (value is RecordingPreparedSpan) {
    yield* _evidenceFragments(value.start, visited);
    yield* _evidenceFragments(value.attributes, visited);
    yield* _evidenceFragments(value.events, visited);
    yield* _evidenceFragments(value.end, visited);
    return;
  }
  if (value is RecordingObservabilityDestination) {
    yield value.name;
    yield* _evidenceFragments(value.logs, visited);
    yield* _evidenceFragments(value.errors, visited);
    yield* _evidenceFragments(value.spanStarts, visited);
    yield* _evidenceFragments(value.spans, visited);
    return;
  }
  if (value is Map<Object?, Object?>) {
    if (!visited.add(value)) return;
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw StateError(
          'Observability evidence contains a non-string map key.',
        );
      }
      yield entry.key! as String;
      yield* _evidenceFragments(entry.value, visited);
    }
    return;
  }
  if (value is Iterable<Object?>) {
    if (!visited.add(value)) return;
    for (final item in value) {
      yield* _evidenceFragments(item, visited);
    }
    return;
  }
  if (value is PreparedObservabilityValue) {
    yield* _evidenceFragments(value.value, visited);
    return;
  }
  throw StateError(
    'Observability evidence contains unsupported type ${value.runtimeType}.',
  );
}
