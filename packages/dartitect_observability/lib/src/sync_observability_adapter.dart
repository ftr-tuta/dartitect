import 'package:dartitect_sync/dartitect_sync.dart';

import 'context.dart';
import 'logging.dart';
import 'privacy.dart';

/// Explicit application-owned projection for a typed sync value.
abstract interface class ObservabilityValueClassifier<T> {
  /// Projects [value] into a supported value with mandatory classifications.
  ObservabilityClassifiedValue<Object?> classify(T value);
}

/// Callback-backed typed value classifier.
final class CallbackObservabilityValueClassifier<T>
    implements ObservabilityValueClassifier<T> {
  /// Creates an explicit classifier callback.
  const CallbackObservabilityValueClassifier(this.callback);

  /// Projection callback.
  final ObservabilityClassifiedValue<Object?> Function(T value) callback;

  @override
  ObservabilityClassifiedValue<Object?> classify(T value) => callback(value);
}

/// Payload-safe bridge from [SyncObserver] lifecycle facts to named logs.
///
/// Run IDs are always classified as `operation.run_id`. Dataset keys are
/// omitted unless [keyClassifier] explicitly projects them. No value is ever
/// interpolated into a message.
final class SyncObservabilityAdapter<K> implements SyncObserver<K> {
  /// Creates a bridge around a runtime-local [logger].
  SyncObservabilityAdapter({required this.logger, this.keyClassifier});

  /// Runtime-local logger.
  final DartitectLogger logger;

  /// Optional explicit projection for dataset keys.
  final ObservabilityValueClassifier<K>? keyClassifier;

  /// Classifier or logger failures isolated from sync behavior.
  int get failureCount => classifierFailureCount + loggerFailureCount;

  /// Dataset-key classifier failures.
  int classifierFailureCount = 0;

  /// Logger failures.
  int loggerFailureCount = 0;

  @override
  void runStarted(String runId, int datasetCount) => _emit(
    name: 'sync.run.started',
    attributes: <String, Object?>{
      'sync.run_id': _runId(runId),
      'sync.dataset_count': ObservabilityClassifiedValue<Object?>(
        datasetCount,
        classes: <ObservabilityDataClass>{ObservabilityDataClass.safeCount},
      ),
    },
  );

  @override
  void datasetStarted(String runId, K key) => _emit(
    name: 'sync.dataset.started',
    attributes: <String, Object?>{
      'sync.run_id': _runId(runId),
      if (_classifyKey(key) case final classified?)
        'sync.dataset_key': classified,
    },
  );

  @override
  void datasetEnded(String runId, K key, String outcome) => _emit(
    name: 'sync.dataset.ended',
    attributes: <String, Object?>{
      'sync.run_id': _runId(runId),
      if (_classifyKey(key) case final classified?)
        'sync.dataset_key': classified,
      'sync.outcome': _outcome(outcome),
    },
  );

  @override
  void runEnded(String runId, String outcome) => _emit(
    name: 'sync.run.ended',
    attributes: <String, Object?>{
      'sync.run_id': _runId(runId),
      'sync.outcome': _outcome(outcome),
    },
  );

  ObservabilityClassifiedValue<Object?> _runId(String value) =>
      ObservabilityClassifiedValue<Object?>(
        value,
        classes: <ObservabilityDataClass>{ObservabilityDataClass.runId},
      );

  ObservabilityClassifiedValue<Object?> _outcome(String value) =>
      ObservabilityClassifiedValue<Object?>(
        value,
        classes: <ObservabilityDataClass>{ObservabilityDataClass.safeStatus},
      );

  ObservabilityClassifiedValue<Object?>? _classifyKey(K key) {
    final classifier = keyClassifier;
    if (classifier == null) return null;
    try {
      return classifier.classify(key);
    } on Object {
      classifierFailureCount += 1;
      return null;
    }
  }

  void _emit({required String name, required Map<String, Object?> attributes}) {
    try {
      logger.event(
        ObservabilityLogEvent(
          name: ObservabilityEventName(name),
          level: LogLevel.debug,
          message: () => name,
          context: ObservabilityContext(attributes: attributes),
        ),
      );
    } on Object {
      loggerFailureCount += 1;
    }
  }
}
