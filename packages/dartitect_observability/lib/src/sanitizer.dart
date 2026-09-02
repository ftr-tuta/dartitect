import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'privacy.dart';

/// Deterministic structural budgets for one sanitization operation.
final class ObservabilitySanitizationLimits {
  /// Creates conservative local limits.
  const ObservabilitySanitizationLimits({
    this.maxDepth = 8,
    this.maxCollectionLength = 64,
    this.maxStringCodePoints = 2048,
    this.maxNodes = 1024,
    this.maxTotalTextCodePoints = 16384,
    this.maxStackFrames = 64,
    this.maxClassificationWork = 4096,
  });

  /// Maximum recursive container depth.
  final int maxDepth;

  /// Maximum entries retained from one collection.
  final int maxCollectionLength;

  /// Maximum Unicode code points retained from one string.
  final int maxStringCodePoints;

  /// Maximum values and keys visited across the complete input.
  final int maxNodes;

  /// Maximum Unicode code points inspected across the complete input.
  final int maxTotalTextCodePoints;

  /// Maximum explicitly projected stack frames retained.
  final int maxStackFrames;

  /// Maximum built-in and custom classification operations.
  final int maxClassificationWork;
}

/// Immutable, payload-free counters for one sanitization operation.
final class ObservabilitySanitizationDiagnostics {
  /// Creates an immutable diagnostics snapshot.
  const ObservabilitySanitizationDiagnostics({
    required this.visitedNodes,
    required this.textCodePoints,
    required this.stackFrames,
    required this.classificationWork,
    required this.deniedValues,
    required this.maskedValues,
    required this.unknownObjects,
    required this.cycles,
    required this.truncatedNodes,
    required this.truncatedText,
    required this.truncatedCollections,
    required this.truncatedFrames,
    required this.truncatedClassification,
    required this.classifierFailures,
    required this.projectorFailures,
  }) : allowedValues = 0;

  /// Creates a snapshot with explicit counts for all three policy actions.
  const ObservabilitySanitizationDiagnostics.withActionCounts({
    required this.visitedNodes,
    required this.textCodePoints,
    required this.stackFrames,
    required this.classificationWork,
    required this.deniedValues,
    required this.maskedValues,
    required this.allowedValues,
    required this.unknownObjects,
    required this.cycles,
    required this.truncatedNodes,
    required this.truncatedText,
    required this.truncatedCollections,
    required this.truncatedFrames,
    required this.truncatedClassification,
    required this.classifierFailures,
    required this.projectorFailures,
  });

  /// Creates a zeroed diagnostics snapshot.
  const ObservabilitySanitizationDiagnostics.empty()
    : visitedNodes = 0,
      textCodePoints = 0,
      stackFrames = 0,
      classificationWork = 0,
      deniedValues = 0,
      maskedValues = 0,
      allowedValues = 0,
      unknownObjects = 0,
      cycles = 0,
      truncatedNodes = 0,
      truncatedText = 0,
      truncatedCollections = 0,
      truncatedFrames = 0,
      truncatedClassification = 0,
      classifierFailures = 0,
      projectorFailures = 0;

  /// Nodes and keys visited.
  final int visitedNodes;

  /// Input text code points inspected.
  final int textCodePoints;

  /// Explicit stack frames retained.
  final int stackFrames;

  /// Classification operations consumed.
  final int classificationWork;

  /// Values denied by policy.
  final int deniedValues;

  /// Values or keys masked by policy.
  final int maskedValues;

  /// Values or keys allowed by policy.
  final int allowedValues;

  /// Objects represented only by safe runtime type.
  final int unknownObjects;

  /// Cyclic references replaced with a constant marker.
  final int cycles;

  /// Values rejected by the global node budget.
  final int truncatedNodes;

  /// Strings truncated by per-value or total text budgets.
  final int truncatedText;

  /// Collections truncated by their per-collection budget.
  final int truncatedCollections;

  /// Explicit stack frames omitted by the frame budget.
  final int truncatedFrames;

  /// Classification stopped by its global work budget.
  final int truncatedClassification;

  /// Custom classifier failures isolated from sanitization.
  final int classifierFailures;

  /// Explicit projector failures isolated from sanitization.
  final int projectorFailures;
}

/// A value produced by [ObservabilitySanitizer], not forgeable by consumers.
final class PreparedObservabilityValue {
  const PreparedObservabilityValue._(this.value, this.diagnostics);

  /// Deeply immutable JSON-like value or a constant structural marker.
  final Object? value;

  /// Data-free work and privacy counters.
  final ObservabilitySanitizationDiagnostics diagnostics;
}

/// Explicit safe projection of an error.
final class ObservabilityErrorProjection {
  /// Creates an error projection without retaining the original error object.
  ObservabilityErrorProjection({required this.type, this.message}) {
    if (!_typePattern.hasMatch(type)) {
      throw ArgumentError.value(
        type,
        'type',
        'must be a static runtime or domain error type',
      );
    }
  }

  /// Static runtime or domain error type.
  final String type;

  /// Optional explicitly classified error message.
  final ObservabilityClassifiedValue<String>? message;

  static final RegExp _typePattern = RegExp(
    r'^[A-Za-z_][A-Za-z0-9_.-]{0,119}$',
  );
}

/// Explicit stack text whose frames may be inspected within strict budgets.
final class ObservabilityStackTraceProjection {
  /// Creates a projection from text already selected by application code.
  const ObservabilityStackTraceProjection(this.text);

  /// Stack text to sanitize and split into bounded frames.
  final String text;
}

/// Adds application-owned classifications without projecting a value.
abstract interface class ObservabilityDataClassifier {
  /// Returns classifications for [value]. Implementations must be pure.
  Iterable<ObservabilityDataClass> classify(
    Object? value, {
    String? key,
    ObservabilityDataClass? container,
  });
}

/// Explicitly projects an otherwise unknown object into supported values.
abstract interface class ObservabilityValueProjector {
  /// Whether this projector owns [value].
  bool supports(Object value);

  /// Projects [value] and attaches mandatory classifications.
  ObservabilityClassifiedValue<Object?> project(Object value);
}

/// Destination-aware, bounded structured sanitizer.
final class ObservabilitySanitizer {
  /// Creates a sanitizer with immutable classifier and projector registries.
  ObservabilitySanitizer({
    required this.policy,
    Iterable<ObservabilityDataClassifier> classifiers =
        const <ObservabilityDataClassifier>[],
    Iterable<ObservabilityValueProjector> projectors =
        const <ObservabilityValueProjector>[],
    this.limits = const ObservabilitySanitizationLimits(),
  }) : classifiers = List<ObservabilityDataClassifier>.unmodifiable(
         classifiers,
       ),
       projectors = List<ObservabilityValueProjector>.unmodifiable(projectors) {
    _validateLimits(limits);
  }

  /// Privacy policy applied to every value and descendant.
  final ObservabilityPrivacyPolicy policy;

  /// Application-owned classifiers, called within the classification budget.
  final List<ObservabilityDataClassifier> classifiers;

  /// Explicit projectors for otherwise unknown object types.
  final List<ObservabilityValueProjector> projectors;

  /// Deterministic structural budgets.
  final ObservabilitySanitizationLimits limits;

  /// Shares classifier, projector, and inline-detection work across a
  /// synchronous set of destination preparations.
  ///
  /// The session exists only for [prepare] and is discarded before this method
  /// returns, so it cannot retain raw values in queues or runtime state.
  static T shareDestinationPreparation<T>(T Function() prepare) {
    if (Zone.current[_sharedPreparationZoneKey] != null) return prepare();
    return runZoned(
      prepare,
      zoneValues: <Object?, Object?>{
        _sharedPreparationZoneKey: _SharedPreparation(),
      },
    );
  }

  /// Produces an unforgeable prepared value and immutable diagnostics.
  PreparedObservabilityValue prepare(
    Object? value, {
    required ObservabilityDestinationKind destination,
    String? destinationName,
    String? key,
    Set<ObservabilityDataClass> classes = const <ObservabilityDataClass>{},
  }) {
    final state = _SanitizationState(
      sanitizer: this,
      destination: destination,
      destinationName: destinationName,
    );
    final prepared = state.visit(
      value,
      key: key,
      explicitClasses: classes,
      depth: 0,
      structuralAccess: false,
    );
    return PreparedObservabilityValue._(
      identical(prepared, _denied) ? '[DENIED]' : prepared,
      state.snapshot(),
    );
  }

  /// Convenience projection for inspection and tests.
  ///
  /// Destination adapters should require prepared event types instead.
  Object? sanitize(
    Object? value, {
    required ObservabilityDestinationKind destination,
    String? destinationName,
    String? key,
    Set<ObservabilityDataClass> classes = const <ObservabilityDataClass>{},
  }) => prepare(
    value,
    destination: destination,
    destinationName: destinationName,
    key: key,
    classes: classes,
  ).value;

  /// Safely projects an error without invoking `error.toString()`.
  PreparedObservabilityValue prepareError(
    Object error, {
    required ObservabilityDestinationKind destination,
    String? destinationName,
  }) => prepare(
    error is ObservabilityErrorProjection
        ? error
        : ObservabilityErrorProjection(type: _safeRuntimeType(error)),
    destination: destination,
    destinationName: destinationName,
    classes: <ObservabilityDataClass>{ObservabilityDataClass.safeMetadata},
  );

  /// Omits arbitrary [StackTrace] implementations instead of stringifying.
  PreparedObservabilityValue prepareStackTrace(
    Object stackTrace, {
    required ObservabilityDestinationKind destination,
    String? destinationName,
  }) => prepare(
    stackTrace is ObservabilityStackTraceProjection
        ? stackTrace
        : '[STACK_TRACE_OMITTED]',
    destination: destination,
    destinationName: destinationName,
    classes: <ObservabilityDataClass>{ObservabilityDataClass.errorStackTrace},
  );
}

final class _SanitizationState {
  _SanitizationState({
    required this.sanitizer,
    required this.destination,
    required this.destinationName,
  });

  final ObservabilitySanitizer sanitizer;
  final ObservabilityDestinationKind destination;
  final String? destinationName;
  final HashSet<Object> activeContainers = HashSet<Object>.identity();

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

  Object? visit(
    Object? input, {
    required String? key,
    required Set<ObservabilityDataClass> explicitClasses,
    required int depth,
    required bool structuralAccess,
    ObservabilityDataClass? container,
  }) {
    if (!_takeNode()) return '[NODE_BUDGET]';
    if (depth > sanitizer.limits.maxDepth) return '[MAX_DEPTH]';

    var value = input;
    final classes = <ObservabilityDataClass>{...explicitClasses};
    while (value is ObservabilityClassifiedValue<Object?>) {
      classes.addAll(value.classes);
      value = value.value;
    }
    if (!_isSupported(value)) {
      final projected = _project(value);
      if (projected != null) {
        classes.addAll(projected.classes);
        value = projected.value;
      }
    }
    final classification = _classify(value, key: key, container: container);
    if (classification.denied) {
      deniedValues += 1;
      return _denied;
    }
    classes.addAll(classification.classes);

    final isContainer =
        !_isBinaryValue(value) &&
        (value is Map<Object?, Object?> ||
            value is Iterable<Object?> && value is! String);
    final decision = sanitizer.policy.explain(
      destination: destination,
      destinationName: destinationName,
      classes: classes,
    );
    var action = decision.action;
    if (isContainer && structuralAccess && classes.isEmpty) {
      action = ObservabilityPrivacyAction.allow;
    }
    if (action == ObservabilityPrivacyAction.deny) {
      deniedValues += 1;
      return _denied;
    }
    if (action == ObservabilityPrivacyAction.mask) {
      maskedValues += 1;
      return _mask(value);
    }
    allowedValues += 1;

    if (value == null || value is bool) return value;
    if (value is num) return value;
    if (value is String) return _sanitizeInline(_boundedText(value));
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Duration) return value.inMicroseconds;
    if (value is Enum) return value.name;
    final binaryMetadata = _binaryMetadata(value);
    if (binaryMetadata != null) return binaryMetadata;
    if (value is Uri) return _sanitizeUri(value, depth: depth);
    if (value is ObservabilityErrorProjection) {
      return _sanitizeError(value, depth: depth);
    }
    if (value is ObservabilityStackTraceProjection) {
      return _sanitizeStack(value.text);
    }
    if (value is Map<Object?, Object?>) {
      return _sanitizeMap(
        value,
        depth: depth,
        container: _structuralContainer(classes) ?? container,
      );
    }
    if (value is Iterable<Object?>) {
      return _sanitizeIterable(
        value,
        depth: depth,
        container: _structuralContainer(classes) ?? container,
      );
    }
    unknownObjects += 1;
    return '[${_safeRuntimeType(value)}]';
  }

  Object _sanitizeMap(
    Map<Object?, Object?> input, {
    required int depth,
    required ObservabilityDataClass? container,
  }) {
    if (!activeContainers.add(input)) {
      cycles += 1;
      return '[CYCLE]';
    }
    try {
      final output = <String, Object?>{};
      var retained = 0;
      var maskedKeyIndex = 0;
      var collisionIndex = 0;
      for (final entry in input.entries) {
        if (retained >= sanitizer.limits.maxCollectionLength) {
          truncatedCollections += 1;
          output['_truncated_entries'] = '[TRUNCATED]';
          break;
        }
        if (!_takeNode()) {
          output['_node_budget'] = '[NODE_BUDGET]';
          break;
        }
        final keyResult = _sanitizeKey(entry.key, container: container);
        if (keyResult.denied) continue;
        var outputKey = keyResult.value;
        if (keyResult.masked) {
          maskedKeyIndex += 1;
          outputKey = '[MASKED_KEY_$maskedKeyIndex]';
        }
        if (output.containsKey(outputKey)) {
          collisionIndex += 1;
          outputKey = keyResult.masked
              ? '[MASKED_KEY_${++maskedKeyIndex}]'
              : '[COLLIDING_KEY_$collisionIndex]';
        }
        final child = visit(
          entry.value,
          key: keyResult.originalString,
          explicitClasses: const <ObservabilityDataClass>{},
          depth: depth + 1,
          structuralAccess: true,
          container: container,
        );
        if (identical(child, _denied)) continue;
        output[outputKey] = child;
        retained += 1;
      }
      return Map<String, Object?>.unmodifiable(output);
    } finally {
      activeContainers.remove(input);
    }
  }

  Object _sanitizeIterable(
    Iterable<Object?> input, {
    required int depth,
    required ObservabilityDataClass? container,
  }) {
    if (!activeContainers.add(input)) {
      cycles += 1;
      return '[CYCLE]';
    }
    try {
      final output = <Object?>[];
      final iterator = input.iterator;
      while (output.length < sanitizer.limits.maxCollectionLength &&
          iterator.moveNext()) {
        final child = visit(
          iterator.current,
          key: null,
          explicitClasses: const <ObservabilityDataClass>{},
          depth: depth + 1,
          structuralAccess: true,
          container: container,
        );
        output.add(identical(child, _denied) ? '[DENIED]' : child);
      }
      if (iterator.moveNext()) {
        truncatedCollections += 1;
        output.add('[TRUNCATED]');
      }
      return List<Object?>.unmodifiable(output);
    } finally {
      activeContainers.remove(input);
    }
  }

  _PreparedKey _sanitizeKey(
    Object? input, {
    required ObservabilityDataClass? container,
  }) {
    final projected = switch (input) {
      final String value => _boundedText(value),
      final bool value => value ? 'true' : 'false',
      final num value => value.toString(),
      final Enum value => value.name,
      _ => null,
    };
    final classification = _classify(
      projected,
      key: projected,
      container: container,
      keyPosition: true,
    );
    if (classification.denied) {
      deniedValues += 1;
      return const _PreparedKey.denied();
    }
    final decision = sanitizer.policy.explain(
      destination: destination,
      destinationName: destinationName,
      classes: classification.classes,
    );
    if (decision.action == ObservabilityPrivacyAction.deny) {
      deniedValues += 1;
      return const _PreparedKey.denied();
    }
    if (decision.action == ObservabilityPrivacyAction.mask ||
        projected == null) {
      maskedValues += 1;
      return _PreparedKey.masked(projected);
    }
    allowedValues += 1;
    return _PreparedKey.allowed(_sanitizeInline(projected));
  }

  Object _sanitizeUri(Uri uri, {required int depth}) {
    final output = <String, Object?>{
      if (uri.scheme.isNotEmpty)
        'scheme': _sanitizeInline(_boundedText(uri.scheme)),
      if (uri.host.isNotEmpty) 'host': _sanitizeInline(_boundedText(uri.host)),
      if (uri.hasPort) 'port': uri.port,
    };
    if (uri.path.isNotEmpty) {
      final path = visit(
        uri.path,
        key: 'path',
        explicitClasses: <ObservabilityDataClass>{
          ObservabilityDataClass.httpPath,
        },
        depth: depth + 1,
        structuralAccess: false,
      );
      if (!identical(path, _denied)) output['path'] = path;
    }
    if (uri.hasQuery) {
      final query = visit(
        uri.query,
        key: 'query',
        explicitClasses: <ObservabilityDataClass>{
          ObservabilityDataClass.httpQuery,
        },
        depth: depth + 1,
        structuralAccess: false,
      );
      if (!identical(query, _denied)) output['query'] = query;
    }
    return Map<String, Object?>.unmodifiable(output);
  }

  Object _sanitizeError(
    ObservabilityErrorProjection error, {
    required int depth,
  }) {
    final output = <String, Object?>{'type': _boundedText(error.type)};
    if (error.message case final message?) {
      final prepared = visit(
        message,
        key: 'message',
        explicitClasses: <ObservabilityDataClass>{
          ObservabilityDataClass.errorMessage,
        },
        depth: depth + 1,
        structuralAccess: false,
      );
      if (!identical(prepared, _denied)) output['message'] = prepared;
    }
    return Map<String, Object?>.unmodifiable(output);
  }

  Object _sanitizeStack(String text) {
    final bounded = _boundedText(text);
    final output = <String>[];
    for (final frame in bounded.split('\n')) {
      if (output.length >= sanitizer.limits.maxStackFrames) {
        truncatedFrames += 1;
        break;
      }
      output.add(
        frame.replaceAll(RegExp(r'file:///[\w./%+~-]+'), 'file:///[PATH]'),
      );
      stackFrames += 1;
    }
    return List<String>.unmodifiable(output);
  }

  _ClassificationResult _classify(
    Object? value, {
    required String? key,
    required ObservabilityDataClass? container,
    bool keyPosition = false,
  }) {
    final shared = _sharedPreparation;
    final cacheKey = _ClassificationCacheKey(
      value,
      key,
      container,
      keyPosition,
    );
    if (shared != null && shared.classifications.containsKey(cacheKey)) {
      return shared.classifications[cacheKey]!;
    }
    _ClassificationResult complete(_ClassificationResult result) {
      shared?.classifications[cacheKey] = result;
      return result;
    }

    final output = <ObservabilityDataClass>{};
    if (!_takeClassificationWork()) {
      return complete(const _ClassificationResult.denied());
    }
    if (value == null || value is bool || value is num || value is DateTime) {
      output.add(ObservabilityDataClass.safeMetadata);
    } else if (value is Duration) {
      output.add(ObservabilityDataClass.safeDuration);
    } else if (value is Enum) {
      output.add(ObservabilityDataClass.safeEnum);
    } else if (value is Uri) {
      output.add(ObservabilityDataClass.safeMetadata);
      if (value.path.isNotEmpty) output.add(ObservabilityDataClass.httpPath);
      if (value.hasQuery) output.add(ObservabilityDataClass.httpQuery);
      if (value.userInfo.isNotEmpty)
        output.add(ObservabilityDataClass.credential);
    } else if (_isBinaryValue(value)) {
      output.add(ObservabilityDataClass.safeMetadata);
    }
    if (key != null) {
      output.addAll(_classifyKey(key, container: container));
      if (keyPosition &&
          output.isEmpty &&
          RegExp(r'^[a-z][a-z0-9_.-]{0,63}$').hasMatch(key)) {
        output.add(ObservabilityDataClass.safeMetadata);
      }
    }
    for (final classifier in sanitizer.classifiers) {
      if (!_takeClassificationWork()) {
        return complete(const _ClassificationResult.denied());
      }
      final additions = <ObservabilityDataClass>{};
      try {
        for (final dataClass in classifier.classify(
          value,
          key: key,
          container: container,
        )) {
          if (!_takeClassificationWork()) {
            return complete(const _ClassificationResult.denied());
          }
          additions.add(dataClass);
        }
      } on Object {
        classifierFailures += 1;
        return complete(const _ClassificationResult.denied());
      }
      output.addAll(additions);
    }
    return complete(_ClassificationResult.allowed(output));
  }

  Set<ObservabilityDataClass> _classifyKey(
    String key, {
    required ObservabilityDataClass? container,
  }) {
    if (!_takeClassificationWork()) return <ObservabilityDataClass>{};
    final normalized = key.toLowerCase().replaceAll('-', '_');
    final output = <ObservabilityDataClass>{};
    if (container == ObservabilityDataClass.httpHeader) {
      output.add(ObservabilityDataClass.httpHeader);
    }
    if (_hasAny(normalized, const <String>[
      'authorization',
      'proxy_authorization',
    ])) {
      output
        ..add(ObservabilityDataClass.httpHeader)
        ..add(ObservabilityDataClass.httpAuthorization)
        ..add(ObservabilityDataClass.token);
    } else if (_hasAny(normalized, const <String>['cookie', 'set_cookie'])) {
      output
        ..add(ObservabilityDataClass.httpHeader)
        ..add(ObservabilityDataClass.httpCookie)
        ..add(ObservabilityDataClass.cookie);
    } else if (_hasAny(normalized, const <String>['token', 'jwt'])) {
      output.add(ObservabilityDataClass.token);
    } else if (_hasAny(normalized, const <String>['password', 'passwd'])) {
      output.add(ObservabilityDataClass.password);
    } else if (_hasAny(normalized, const <String>[
      'secret',
      'api_key',
      'apikey',
    ])) {
      output.add(ObservabilityDataClass.secret);
    } else if (_hasAny(normalized, const <String>['email'])) {
      output.add(ObservabilityDataClass.email);
    } else if (_hasAny(normalized, const <String>['cpf'])) {
      output.add(ObservabilityDataClass.cpf);
    } else if (_hasAny(normalized, const <String>['cnpj'])) {
      output.add(ObservabilityDataClass.cnpj);
    } else if (_hasAny(normalized, const <String>['user_id', 'userid'])) {
      output.add(ObservabilityDataClass.userId);
    } else if (_hasAny(normalized, const <String>['path', 'file'])) {
      output.add(ObservabilityDataClass.filePath);
    } else if (_hasAny(normalized, const <String>['query'])) {
      output.add(ObservabilityDataClass.httpQuery);
    }
    return output;
  }

  ObservabilityClassifiedValue<Object?>? _project(Object? value) {
    if (value == null) return null;
    final shared = _sharedPreparation;
    if (shared != null && shared.projections.containsKey(value)) {
      return shared.projections[value];
    }
    ObservabilityClassifiedValue<Object?>? complete(
      ObservabilityClassifiedValue<Object?>? result,
    ) {
      shared?.projections[value] = result;
      return result;
    }

    for (final projector in sanitizer.projectors) {
      if (!_takeClassificationWork()) return complete(null);
      try {
        if (!projector.supports(value)) continue;
        if (!_takeClassificationWork()) return complete(null);
        return complete(projector.project(value));
      } on Object {
        projectorFailures += 1;
        return complete(null);
      }
    }
    return complete(null);
  }

  Object _mask(Object? value) {
    if (value is String) {
      return sanitizer.policy.masking.mask(_boundedText(value));
    }
    if (value is num) {
      return sanitizer.policy.masking.mask(value.toString());
    }
    if (value is DateTime) {
      return sanitizer.policy.masking.mask(value.toUtc().toIso8601String());
    }
    if (value is Duration) {
      return sanitizer.policy.masking.mask('${value.inMicroseconds}');
    }
    if (value is Enum) return sanitizer.policy.masking.mask(value.name);
    return sanitizer.policy.masking.replacement;
  }

  String _sanitizeInline(String input) {
    final plan = _inlinePlan(input);
    if (plan.budgetExceeded) return '[CLASSIFICATION_BUDGET]';
    if (plan.spans.isEmpty) return input;
    final output = StringBuffer();
    var cursor = 0;
    for (final span in plan.spans) {
      if (span.start > cursor)
        output.write(input.substring(cursor, span.start));
      final source = input.substring(span.start, span.end);
      final decision = sanitizer.policy.explain(
        destination: destination,
        destinationName: destinationName,
        classes: span.classes,
      );
      switch (decision.action) {
        case ObservabilityPrivacyAction.allow:
          output.write(source);
        case ObservabilityPrivacyAction.mask:
          maskedValues += 1;
          output.write(sanitizer.policy.masking.mask(source));
        case ObservabilityPrivacyAction.deny:
          deniedValues += 1;
          output.write('[REDACTED]');
      }
      cursor = span.end;
    }
    if (cursor < input.length) output.write(input.substring(cursor));
    return output.toString();
  }

  _InlinePlan _inlinePlan(String input) {
    final shared = _sharedPreparation;
    final cached = shared?.inlinePlans[input];
    if (cached != null) return cached;
    final candidates = <_InlineCandidate>[];
    for (final detector in _inlineDetectors) {
      if (!_takeClassificationWork()) {
        return _cacheInlinePlan(
          shared,
          input,
          const _InlinePlan.budgetExceeded(),
        );
      }
      for (final match in detector.pattern.allMatches(input)) {
        if (!_takeClassificationWork()) {
          return _cacheInlinePlan(
            shared,
            input,
            const _InlinePlan.budgetExceeded(),
          );
        }
        if (match.start < match.end) {
          candidates.add(
            _InlineCandidate(match.start, match.end, detector.dataClass),
          );
        }
      }
    }
    if (candidates.isEmpty) {
      return _cacheInlinePlan(shared, input, const _InlinePlan.empty());
    }
    final boundaries = <int>{
      for (final candidate in candidates) candidate.start,
      for (final candidate in candidates) candidate.end,
    }.toList()..sort();
    final spans = <_InlineSpan>[];
    for (var index = 0; index + 1 < boundaries.length; index += 1) {
      final start = boundaries[index];
      final end = boundaries[index + 1];
      final classes = <ObservabilityDataClass>{
        for (final candidate in candidates)
          if (candidate.start < end && candidate.end > start)
            candidate.dataClass,
      };
      if (classes.isNotEmpty) spans.add(_InlineSpan(start, end, classes));
    }
    return _cacheInlinePlan(
      shared,
      input,
      _InlinePlan(List<_InlineSpan>.unmodifiable(spans)),
    );
  }

  String _boundedText(String input) {
    final remaining = sanitizer.limits.maxTotalTextCodePoints - textCodePoints;
    if (remaining <= 0) {
      truncatedText += 1;
      return '[TEXT_BUDGET]';
    }
    final limit = remaining < sanitizer.limits.maxStringCodePoints
        ? remaining
        : sanitizer.limits.maxStringCodePoints;
    final points = <int>[];
    final iterator = input.runes.iterator;
    while (points.length < limit && iterator.moveNext()) {
      points.add(iterator.current);
    }
    textCodePoints += points.length;
    if (iterator.moveNext()) {
      truncatedText += 1;
      return '${String.fromCharCodes(points)}…[TRUNCATED]';
    }
    return String.fromCharCodes(points);
  }

  bool _takeNode() {
    if (visitedNodes >= sanitizer.limits.maxNodes) {
      truncatedNodes += 1;
      return false;
    }
    visitedNodes += 1;
    return true;
  }

  bool _takeClassificationWork() {
    if (classificationWork >= sanitizer.limits.maxClassificationWork) {
      truncatedClassification += 1;
      return false;
    }
    classificationWork += 1;
    return true;
  }
}

final class _PreparedKey {
  const _PreparedKey._({
    required this.value,
    required this.originalString,
    required this.denied,
    required this.masked,
  });

  const _PreparedKey.allowed(String value)
    : this._(value: value, originalString: value, denied: false, masked: false);

  const _PreparedKey.masked(String? original)
    : this._(
        value: '[MASKED_KEY]',
        originalString: original,
        denied: false,
        masked: true,
      );

  const _PreparedKey.denied()
    : this._(value: '', originalString: null, denied: true, masked: false);

  final String value;
  final String? originalString;
  final bool denied;
  final bool masked;
}

final class _ClassificationResult {
  const _ClassificationResult.allowed(this.classes) : denied = false;

  const _ClassificationResult.denied()
    : classes = const <ObservabilityDataClass>{},
      denied = true;

  final Set<ObservabilityDataClass> classes;
  final bool denied;
}

final Object _sharedPreparationZoneKey = Object();

_SharedPreparation? get _sharedPreparation =>
    Zone.current[_sharedPreparationZoneKey] as _SharedPreparation?;

final class _SharedPreparation {
  final Map<_ClassificationCacheKey, _ClassificationResult> classifications =
      <_ClassificationCacheKey, _ClassificationResult>{};
  final HashMap<Object, ObservabilityClassifiedValue<Object?>?> projections =
      HashMap<Object, ObservabilityClassifiedValue<Object?>?>.identity();
  final Map<String, _InlinePlan> inlinePlans = <String, _InlinePlan>{};
}

final class _ClassificationCacheKey {
  const _ClassificationCacheKey(
    this.value,
    this.key,
    this.container,
    this.keyPosition,
  );

  final Object? value;
  final String? key;
  final ObservabilityDataClass? container;
  final bool keyPosition;

  @override
  bool operator ==(Object other) =>
      other is _ClassificationCacheKey &&
      identical(value, other.value) &&
      key == other.key &&
      container == other.container &&
      keyPosition == other.keyPosition;

  @override
  int get hashCode =>
      Object.hash(identityHashCode(value), key, container, keyPosition);
}

final class _InlineCandidate {
  const _InlineCandidate(this.start, this.end, this.dataClass);

  final int start;
  final int end;
  final ObservabilityDataClass dataClass;
}

final class _InlineSpan {
  _InlineSpan(this.start, this.end, Set<ObservabilityDataClass> classes)
    : classes = Set<ObservabilityDataClass>.unmodifiable(classes);

  final int start;
  final int end;
  final Set<ObservabilityDataClass> classes;
}

final class _InlinePlan {
  const _InlinePlan(this.spans) : budgetExceeded = false;

  const _InlinePlan.empty()
    : spans = const <_InlineSpan>[],
      budgetExceeded = false;

  const _InlinePlan.budgetExceeded()
    : spans = const <_InlineSpan>[],
      budgetExceeded = true;

  final List<_InlineSpan> spans;
  final bool budgetExceeded;
}

_InlinePlan _cacheInlinePlan(
  _SharedPreparation? shared,
  String input,
  _InlinePlan plan,
) {
  shared?.inlinePlans[input] = plan;
  return plan;
}

final class _InlineDetector {
  const _InlineDetector(this.pattern, this.dataClass);

  final RegExp pattern;
  final ObservabilityDataClass dataClass;
}

final List<_InlineDetector> _inlineDetectors = <_InlineDetector>[
  _InlineDetector(
    RegExp(
      r'\b(?:authorization\s*[:=]\s*|bearer\s+|basic\s+)[^\s,;]+',
      caseSensitive: false,
    ),
    ObservabilityDataClass.token,
  ),
  _InlineDetector(
    RegExp(
      r'\b(?:token|password|passwd|secret|api[_-]?key|cookie)\s*[:=]\s*[^\s,;]+',
      caseSensitive: false,
    ),
    ObservabilityDataClass.credential,
  ),
  _InlineDetector(
    RegExp(
      r'\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}(?:\.[A-Za-z0-9_-]{4,})?\b',
    ),
    ObservabilityDataClass.jwt,
  ),
  _InlineDetector(
    RegExp(r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', caseSensitive: false),
    ObservabilityDataClass.email,
  ),
  _InlineDetector(
    RegExp(r'\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b'),
    ObservabilityDataClass.cpf,
  ),
  _InlineDetector(
    RegExp(r'\b\d{2}\.?\d{3}\.?\d{3}/?\d{4}-?\d{2}\b'),
    ObservabilityDataClass.cnpj,
  ),
  _InlineDetector(
    RegExp(
      r'\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b',
      caseSensitive: false,
    ),
    ObservabilityDataClass.uuid,
  ),
  _InlineDetector(
    RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'),
    ObservabilityDataClass.ipAddress,
  ),
  _InlineDetector(RegExp(r'\?[^\s#]+'), ObservabilityDataClass.httpQuery),
];

const Object _denied = _DeniedValue();

final class _DeniedValue {
  const _DeniedValue();
}

bool _isSupported(Object? value) =>
    value == null ||
    value is bool ||
    value is num ||
    value is String ||
    value is Uri ||
    value is DateTime ||
    value is Duration ||
    value is Enum ||
    value is TypedData ||
    value is ByteBuffer ||
    _isBinaryStream(value) ||
    value is Map<Object?, Object?> ||
    value is Iterable<Object?> ||
    value is ObservabilityErrorProjection ||
    value is ObservabilityStackTraceProjection;

bool _isBinaryValue(Object? value) =>
    value is TypedData || value is ByteBuffer || _isBinaryStream(value);

bool _isBinaryStream(Object? value) =>
    value is Stream<Uint8List> ||
    value is Stream<List<int>> ||
    value is Stream<TypedData> ||
    value is Stream<ByteBuffer>;

Map<String, Object?>? _binaryMetadata(Object? value) {
  if (value is Uint8List) {
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      'kind': 'uint8_list',
      'length': value.lengthInBytes,
    });
  }
  if (value is ByteData) {
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      'kind': 'byte_data',
      'length': value.lengthInBytes,
    });
  }
  if (value is TypedData) {
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      'kind': 'typed_data',
      'length': value.lengthInBytes,
    });
  }
  if (value is ByteBuffer) {
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      'kind': 'byte_buffer',
      'length': value.lengthInBytes,
    });
  }
  if (_isBinaryStream(value)) {
    return Map<String, Object?>.unmodifiable(const <String, Object?>{
      'kind': 'binary_stream',
      'length': null,
    });
  }
  return null;
}

ObservabilityDataClass? _structuralContainer(
  Set<ObservabilityDataClass> classes,
) {
  for (final candidate in <ObservabilityDataClass>[
    ObservabilityDataClass.httpAuthorization,
    ObservabilityDataClass.httpCookie,
    ObservabilityDataClass.httpHeader,
    ObservabilityDataClass.httpRequestBody,
    ObservabilityDataClass.httpResponseBody,
    ObservabilityDataClass.httpBody,
    ObservabilityDataClass.httpQuery,
  ]) {
    if (classes.contains(candidate)) return candidate;
  }
  return null;
}

bool _hasAny(String input, List<String> needles) {
  for (final needle in needles) {
    if (input.contains(needle)) return true;
  }
  return false;
}

String _safeRuntimeType(Object value) => value.runtimeType.toString();

void _validateLimits(ObservabilitySanitizationLimits limits) {
  final values = <String, int>{
    'maxDepth': limits.maxDepth,
    'maxCollectionLength': limits.maxCollectionLength,
    'maxStringCodePoints': limits.maxStringCodePoints,
    'maxNodes': limits.maxNodes,
    'maxTotalTextCodePoints': limits.maxTotalTextCodePoints,
    'maxStackFrames': limits.maxStackFrames,
    'maxClassificationWork': limits.maxClassificationWork,
  };
  for (final entry in values.entries) {
    if (entry.value <= 0) {
      throw ArgumentError.value(entry.value, entry.key, 'must be > 0');
    }
  }
}
