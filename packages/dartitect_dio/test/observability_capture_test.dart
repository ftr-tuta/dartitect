import 'dart:async';
import 'dart:typed_data';

import 'package:dartitect_dio/dartitect_dio.dart';
import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test('metadata-only default never inspects request surfaces', () {
    final logger = _RecordingLogger();
    final interceptor = DioObservabilityInterceptor(
      logger: logger,
      routeTemplate: (_) => RouteTemplate('/accounts/:accountId'),
    );
    final body = _ExplosiveBody();
    final options = RequestOptions(
      path: '/accounts/private',
      method: 'POST',
      data: body,
      queryParameters: <String, Object?>{'token': 'top-secret'},
      headers: <String, Object?>{'Authorization': 'Bearer top-secret'},
    );

    interceptor.onRequest(options, RequestInterceptorHandler());

    expect(body.toStringCalls, 0);
    expect(logger.events, hasLength(1));
    final attributes = logger.events.single.context!.attributes;
    expect(attributes.keys, <String>{
      'http.phase',
      'http.method',
      'http.route_template',
    });
  });

  test('diagnostic capture wraps JSON surfaces in explicit classes', () {
    final logger = _RecordingLogger();
    final interceptor = DioObservabilityInterceptor(
      logger: logger,
      routeTemplate: (_) => RouteTemplate('/accounts/:accountId'),
      capturePolicy: const DioObservabilityCapturePolicy.diagnostic(
        mode: DioObservabilityCaptureMode.request,
        captureHeaders: true,
        captureBody: true,
        captureQuery: true,
      ),
    );
    final options = RequestOptions(
      path: '/accounts/private',
      method: 'POST',
      data: <String, Object?>{
        'email': 'person@example.com',
        'password': 'top-secret',
      },
      queryParameters: <String, Object?>{'token': 'top-secret'},
      headers: <String, Object?>{'Authorization': 'Bearer top-secret'},
    );

    interceptor.onRequest(options, RequestInterceptorHandler());

    final attributes = logger.events.single.context!.attributes;
    expect(
      (attributes['http.query']! as ObservabilityClassifiedValue<Object?>)
          .classes,
      contains(ObservabilityDataClass.httpQuery),
    );
    expect(
      (attributes['http.request.headers']!
              as ObservabilityClassifiedValue<Object?>)
          .classes,
      contains(ObservabilityDataClass.httpHeader),
    );
    expect(
      (attributes['http.request.body']!
              as ObservabilityClassifiedValue<Object?>)
          .classes,
      contains(ObservabilityDataClass.httpRequestBody),
    );
  });

  test(
    'streams, multipart, typed bytes, byte lists, and unknowns are omitted',
    () {
      final logger = _RecordingLogger();
      final interceptor = DioObservabilityInterceptor(
        logger: logger,
        routeTemplate: (_) => RouteTemplate('/upload'),
        capturePolicy: const DioObservabilityCapturePolicy.diagnostic(
          mode: DioObservabilityCaptureMode.request,
          captureBody: true,
        ),
      );

      for (final body in <Object>[
        Stream<List<int>>.value(<int>[1, 2, 3]),
        FormData(),
        Uint8List.fromList(<int>[1, 2, 3]),
        <int>[1, 2, 3],
        _ExplosiveBody(),
      ]) {
        interceptor.onRequest(
          RequestOptions(path: '/upload', method: 'POST', data: body),
          RequestInterceptorHandler(),
        );
      }

      for (final event in logger.events) {
        expect(event.context!.attributes, isNot(contains('http.request.body')));
      }
      expect(interceptor.omittedCaptureCount, 5);
    },
  );

  test(
    'privacy runtime removes captured raw secrets before destinations',
    () async {
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
      final interceptor = DioObservabilityInterceptor(
        logger: runtime.logger,
        routeTemplate: (_) => RouteTemplate('/accounts/:accountId'),
        capturePolicy: const DioObservabilityCapturePolicy.diagnostic(
          mode: DioObservabilityCaptureMode.request,
          captureHeaders: true,
          captureBody: true,
          captureQuery: true,
        ),
      );

      interceptor.onRequest(
        RequestOptions(
          path: '/accounts/private',
          method: 'POST',
          data: <String, Object?>{
            'email': 'person@example.com',
            'password': 'top-secret',
          },
          queryParameters: <String, Object?>{'token': 'top-secret'},
          headers: <String, Object?>{'Authorization': 'Bearer top-secret'},
        ),
        RequestInterceptorHandler(),
      );
      await runtime.flushDetailed();

      expect(events, hasLength(1));
      expect(
        '${events.single.context.attributes}',
        isNot(contains('top-secret')),
      );
      expect(
        '${events.single.context.attributes}',
        isNot(contains('person@example.com')),
      );
      await runtime.disposeAsync();
    },
  );

  test('attach rejects LogInterceptor and duplicate capture', () {
    final logger = _RecordingLogger();
    // dartitect-ignore: DT1051 -- verifies the unsafe interceptor is rejected
    final unsafe = Dio()..interceptors.add(LogInterceptor());
    expect(
      () => DioObservabilityInterceptor.attach(
        unsafe,
        logger: logger,
        routeTemplate: (_) => RouteTemplate('/health'),
      ),
      throwsA(isA<DioObservabilityConflictException>()),
    );
    unsafe.close();

    final dio = Dio();
    DioObservabilityInterceptor.attach(
      dio,
      logger: logger,
      routeTemplate: (_) => RouteTemplate('/health'),
    );
    expect(
      () => DioObservabilityInterceptor.attach(
        dio,
        logger: logger,
        routeTemplate: (_) => RouteTemplate('/health'),
      ),
      throwsA(isA<DioObservabilityConflictException>()),
    );
    dio.close();
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

final class _ExplosiveBody {
  int toStringCalls = 0;

  @override
  String toString() {
    toStringCalls += 1;
    throw StateError('body must not be projected');
  }
}
