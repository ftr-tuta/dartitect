import 'dart:convert';
import 'dart:io';

import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:test/test.dart';

void main() {
  test('four destinations share classification across 1000 events', () async {
    const eventCount = 1000;
    final marker = _Marker();
    final classifier = _CountingClassifier(marker);
    var delivered = 0;
    PreparedLogSinkRegistration sink() => PreparedLogSinkRegistration.borrowed(
      CallbackPreparedLogSink((_) => delivered += 1),
    );

    final runtime = ObservabilityRuntime.withPrivacy(
      privacyPolicy: ObservabilityPrivacyPolicy.fromProfile(
        profile: ObservabilityPrivacyProfile.diagnostic,
      ),
      destinations: <ObservabilityDestinationRegistration>[
        ObservabilityDestinationRegistration.local(
          logSinks: <PreparedLogSinkRegistration>[sink()],
          samplingPolicy: FixedSamplingPolicy(logRate: 1),
          queueCapacity: 2048,
        ),
        for (var index = 1; index <= 3; index++)
          ObservabilityDestinationRegistration.remote(
            name: 'remote_$index',
            logSinks: <PreparedLogSinkRegistration>[sink()],
            samplingPolicy: FixedSamplingPolicy(logRate: 1),
            queueCapacity: 2048,
          ),
      ],
      classifiers: <ObservabilityDataClassifier>[classifier],
    );

    final watch = Stopwatch()..start();
    for (var index = 0; index < eventCount; index++) {
      runtime.logger.info(
        'benchmark.event',
        context: ObservabilityContext(
          attributes: <String, Object?>{'marker': marker, 'index': index},
        ),
      );
    }
    expect(await runtime.flush(const Duration(seconds: 10)), isTrue);
    watch.stop();

    expect(classifier.markerCalls, eventCount);
    expect(delivered, eventCount * 4);
    expect(
      runtime.diagnostics.destinations.values.map(
        (destination) => destination.droppedEvents,
      ),
      everyElement(0),
    );
    await runtime.disposeAsync();
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'benchmark': 'incremental-observability-fanout',
        'metrics': 'informative',
        'events': eventCount,
        'destinations': 4,
        'classifierCallsForMarker': classifier.markerCalls,
        'delivered': delivered,
        'totalMicros': watch.elapsedMicroseconds,
      }),
    );
  });
}

final class _Marker {}

final class _CountingClassifier implements ObservabilityDataClassifier {
  _CountingClassifier(this.marker);

  final _Marker marker;
  var markerCalls = 0;

  @override
  Iterable<ObservabilityDataClass> classify(
    Object? value, {
    String? key,
    ObservabilityDataClass? container,
  }) {
    if (identical(value, marker)) markerCalls += 1;
    return const <ObservabilityDataClass>[];
  }
}
