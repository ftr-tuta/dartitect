import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:dartitect_observability/dartitect_observability_sync.dart';
import 'package:test/test.dart';

void main() {
  test('sync facts classify run IDs and never interpolate typed keys', () {
    final logger = _RecordingLogger();
    final key = _ExplosiveDatasetKey('catalog');
    final adapter = SyncObservabilityAdapter<_ExplosiveDatasetKey>(
      logger: logger,
      keyClassifier: CallbackObservabilityValueClassifier<_ExplosiveDatasetKey>(
        (value) => ObservabilityClassifiedValue<Object?>(
          value.safeCode,
          classes: <ObservabilityDataClass>{ObservabilityDataClass.datasetKey},
        ),
      ),
    );

    adapter
      ..runStarted('private-run-id', 1)
      ..datasetStarted('private-run-id', key)
      ..datasetEnded('private-run-id', key, 'succeeded')
      ..runEnded('private-run-id', 'completed');

    expect(key.toStringCalls, 0);
    expect(logger.events.map((event) => event.name.value), <String>[
      'sync.run.started',
      'sync.dataset.started',
      'sync.dataset.ended',
      'sync.run.ended',
    ]);
    final runId =
        logger.events.first.context!.attributes['sync.run_id']!
            as ObservabilityClassifiedValue<Object?>;
    expect(runId.value, 'private-run-id');
    expect(runId.classes, contains(ObservabilityDataClass.runId));
    final datasetKey =
        logger.events[1].context!.attributes['sync.dataset_key']!
            as ObservabilityClassifiedValue<Object?>;
    expect(datasetKey.value, 'catalog');
    expect(datasetKey.classes, contains(ObservabilityDataClass.datasetKey));
  });

  test('privacy runtime masks sync identifiers before a destination', () async {
    final events = <PreparedLogEvent>[];
    final runtime = ObservabilityRuntime.withPrivacy(
      privacyPolicy: ObservabilityPrivacyPolicy.fromProfile(
        profile: ObservabilityPrivacyProfile.diagnostic,
      ),
      destinations: <ObservabilityDestinationRegistration>[
        ObservabilityDestinationRegistration.local(
          logSinks: <PreparedLogSinkRegistration>[
            PreparedLogSinkRegistration.borrowed(
              CallbackPreparedLogSink(events.add),
            ),
          ],
          samplingPolicy: FixedSamplingPolicy(logRate: 1),
        ),
      ],
    );
    final adapter = SyncObservabilityAdapter<String>(
      logger: runtime.logger,
      keyClassifier: CallbackObservabilityValueClassifier<String>(
        (value) => ObservabilityClassifiedValue<Object?>(
          value,
          classes: <ObservabilityDataClass>{ObservabilityDataClass.datasetKey},
        ),
      ),
    );

    adapter.datasetEnded('private-run-id', 'private-dataset', 'succeeded');
    await runtime.flushDetailed();

    expect(events, hasLength(1));
    expect(
      '${events.single.context.attributes}',
      isNot(contains('private-run-id')),
    );
    expect(
      '${events.single.context.attributes}',
      isNot(contains('private-dataset')),
    );
    await runtime.disposeAsync();
  });

  test('absent or failing key classifiers omit dataset keys', () {
    final logger = _RecordingLogger();
    final absent = SyncObservabilityAdapter<String>(logger: logger);
    absent.datasetStarted('run', 'private');
    expect(
      logger.events.single.context!.attributes,
      isNot(contains('sync.dataset_key')),
    );

    final failing = SyncObservabilityAdapter<String>(
      logger: logger,
      keyClassifier: CallbackObservabilityValueClassifier<String>(
        (_) => throw StateError('classifier failed'),
      ),
    );
    failing.datasetStarted('run', 'private');
    expect(failing.classifierFailureCount, 1);
    expect(
      logger.events.last.context!.attributes,
      isNot(contains('sync.dataset_key')),
    );
  });
}

final class _RecordingLogger extends DartitectLogger {
  final events = <ObservabilityLogEvent>[];

  @override
  void event(ObservabilityLogEvent event) => events.add(event);

  @override
  void log(
    LogLevel level,
    String message, {
    ObservabilityContext? context,
    Object? error,
    StackTrace? stackTrace,
  }) {}
}

final class _ExplosiveDatasetKey {
  _ExplosiveDatasetKey(this.safeCode);

  final String safeCode;
  int toStringCalls = 0;

  @override
  String toString() {
    toStringCalls += 1;
    throw StateError('dataset key must not be interpolated');
  }
}
