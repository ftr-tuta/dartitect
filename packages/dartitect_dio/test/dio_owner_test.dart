import 'dart:async';
import 'dart:typed_data';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_dio/dartitect_dio.dart';
import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test('owned closes and borrowed does not close the real adapter', () {
    final ownedAdapter = _FakeAdapter();
    final owned = DioOwner.create(
      configure: (dio) => dio.httpClientAdapter = ownedAdapter,
    );
    owned.dispose();
    owned.dispose();
    expect(ownedAdapter.closeCalls, 1);
    expect(() => owned.dio, throwsStateError);

    final borrowedAdapter = _FakeAdapter();
    final client = Dio()..httpClientAdapter = borrowedAdapter;
    DioOwner.value(client).dispose();
    expect(borrowedAdapter.closeCalls, 0);
    client.close();
  });

  test('interceptors preserve order and callbacks attach headers', () async {
    final order = <String>[];
    final adapter = _FakeAdapter(
      inspect: (options) {
        expect(options.headers['Authorization'], 'Bearer token');
        expect(options.headers['X-Tenant-Id'], 'tenant');
      },
    );
    final owner = DioOwner.create(
      options: BaseOptions(baseUrl: 'https://example.invalid'),
      interceptors: <Interceptor>[
        InterceptorsWrapper(
          onRequest: (options, handler) {
            order.add('first');
            handler.next(options);
          },
        ),
        DartitectHeadersInterceptor(
          authorization: (_) => 'Bearer token',
          tenant: (_) => 'tenant',
        ),
        InterceptorsWrapper(
          onRequest: (options, handler) {
            order.add('last');
            handler.next(options);
          },
        ),
      ],
      configure: (dio) => dio.httpClientAdapter = adapter,
    );

    await owner.dio.get<void>('/resource');
    expect(order, <String>['first', 'last']);
    owner.dispose();
  });

  test('Dio mapping catches DioException only and keeps stack', () async {
    final options = RequestOptions(path: '/failure');
    final result = await captureDioException<int>(
      () => throw DioException(requestOptions: options),
    );
    expect(result, isA<Err<DioFailure>>());
    expect((result as Err<DioFailure>).failure, isA<DioConfigurationFailure>());
    expect(result.stackTrace, isNot(StackTrace.empty));

    await expectLater(
      captureDioException<int>(() => throw StateError('programming error')),
      throwsStateError,
    );
  });

  test('Dio mapping distinguishes cancellation, transport, and HTTP', () async {
    Future<Result<int, DioFailure>> capture(
      DioExceptionType type, {
      int? status,
    }) => captureDioException<int>(
      () => throw DioException(
        requestOptions: RequestOptions(path: '/secret/42'),
        type: type,
        response: status == null
            ? null
            : Response<void>(
                requestOptions: RequestOptions(path: '/secret/42'),
                statusCode: status,
              ),
      ),
    );

    expect(
      (await capture(DioExceptionType.cancel) as Err<DioFailure>).failure,
      isA<DioCancelledFailure>(),
    );
    expect(
      (await capture(
        DioExceptionType.connectionError,
      ) as Err<DioFailure>).failure,
      isA<DioTransportFailure>(),
    );
    final http =
        (await capture(
              DioExceptionType.badResponse,
              status: 503,
            ) as Err<DioFailure>).failure
            as DioHttpFailure;
    expect(http.statusCode, 503);
  });

  test('owned cancel token cooperates with ResourceOwner', () async {
    final owner = ResourceOwner();
    final token = ownCancelToken(owner, reason: 'session closed');

    await owner.disposeAsync();

    expect(token.isCancelled, isTrue);
    expect(token.cancelError?.error, 'session closed');
  });

  test('cooperative signal cancels one token shared by requests', () async {
    final source = CancellationSource();
    final release = Completer<void>();
    final started = Completer<void>();
    var starts = 0;
    final dio = Dio()
      ..httpClientAdapter = _FakeAdapter(
        inspect: (_) {
          starts += 1;
          if (starts == 2) started.complete();
        },
        waitFor: release.future,
      );
    final token = bindCancelToken(source.signal);
    final first = dio.get<void>(
      'https://example.invalid/one',
      cancelToken: token,
    );
    final second = dio.get<void>(
      'https://example.invalid/two',
      cancelToken: token,
    );
    await started.future;
    expect(starts, 2);

    source.cancel('lane restarted');
    release.complete();

    await expectLater(
      first,
      throwsA(
        isA<DioException>().having(
          (error) => error.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
    await expectLater(
      second,
      throwsA(
        isA<DioException>().having(
          (error) => error.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
    expect(token.cancelError?.error, 'lane restarted');
    dio.close();
  });

  test('direct token cancellation unregisters without cancelling source', () {
    final source = CancellationSource();
    final token = bindCancelToken(source.signal, reason: 'bound reason');

    token.cancel('direct reason');
    source.cancel('source reason');

    expect(source.signal.isCancelled, isTrue);
    expect(token.cancelError?.error, 'direct reason');
  });

  test(
    'instrumentation traces minimal metadata and explicit propagation',
    () async {
      final tracer = _RecordingTracer();
      late RequestOptions captured;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
        ..httpClientAdapter = _FakeAdapter(
          inspect: (options) => captured = options,
        );
      final instrumentation = DioInstrumentation.attach(
        dio,
        tracer: tracer,
        routeTemplate: (_) => RouteTemplate('/people/:personId'),
        propagator: const W3CTracePropagator(),
      );

      await dio.get<void>(
        '/people/identifying-id',
        queryParameters: <String, Object?>{'token': 'secret'},
        data: <String, Object?>{'password': 'secret'},
        options: Options(headers: <String, Object?>{'cookie': 'secret'}),
      );

      expect(tracer.names, <String>['HTTP GET /people/:personId']);
      expect(tracer.attributes.single.keys.toSet(), <String>{
        'http.request.method',
        'http.route',
      });
      expect('${tracer.attributes}', isNot(contains('identifying-id')));
      expect('${tracer.attributes}', isNot(contains('secret')));
      expect(captured.headers['traceparent'], isNotNull);
      expect(instrumentation.activeRequestCount, 0);
      expect(tracer.spans.single.endCalls, 1);
      instrumentation.dispose();
      dio.close();
    },
  );

  test('instrumentation detects duplicate Dartitect and sentry_dio setup', () {
    final dio = Dio();
    final instrumentation = DioInstrumentation.attach(
      dio,
      tracer: _RecordingTracer(),
      routeTemplate: (_) => RouteTemplate('/health'),
    );
    expect(
      () => DioInstrumentation.attach(
        dio,
        tracer: _RecordingTracer(),
        routeTemplate: (_) => RouteTemplate('/health'),
      ),
      throwsA(isA<DioInstrumentationConflictException>()),
    );
    instrumentation.dispose();
    dio.close();

    final sentryConfigured = Dio()..interceptors.add(_SentryDioInterceptor());
    expect(
      () => DioInstrumentation.attach(
        sentryConfigured,
        tracer: _RecordingTracer(),
        routeTemplate: (_) => RouteTemplate('/health'),
      ),
      throwsA(isA<DioInstrumentationConflictException>()),
    );
    sentryConfigured.close();
  });

  test(
    'dispose cancels active spans without touching request payload',
    () async {
      final release = Completer<void>();
      final started = Completer<void>();
      final tracer = _RecordingTracer();
      final dio = Dio()
        ..httpClientAdapter = _FakeAdapter(
          inspect: (_) => started.complete(),
          waitFor: release.future,
        );
      final instrumentation = DioInstrumentation.attach(
        dio,
        tracer: tracer,
        routeTemplate: (_) => RouteTemplate('/private/:resourceId'),
      );

      final request = dio.get<void>('https://example.invalid/private/42');
      await started.future;
      expect(instrumentation.activeRequestCount, 1);
      instrumentation.dispose();
      expect(instrumentation.activeRequestCount, 0);
      expect(tracer.spans.single.status, SpanStatus.cancelled);

      release.complete();
      await request;
      expect(tracer.spans.single.endCalls, 1);
      dio.close();
    },
  );

  test(
    'route templates reject raw URL data and missing routes fail closed',
    () async {
      expect(
        () => RouteTemplate('/people/42'),
        throwsA(isA<InvalidRouteTemplateException>()),
      );
      expect(
        () => RouteTemplate('/people/:id?token=secret'),
        throwsA(isA<InvalidRouteTemplateException>()),
      );
      final observer = _RecordingTelemetryObserver();
      final telemetry = DioTelemetryInterceptor(
        observer,
        routeTemplate: (_) => null,
      );
      final dio = Dio()..httpClientAdapter = _FakeAdapter();
      dio.interceptors.add(telemetry);

      await dio.get<void>(
        'https://example.invalid/people/private-id?token=secret',
      );

      expect(observer.events, isEmpty);
      expect(telemetry.omittedEventCount, 2);
      dio.close();
    },
  );
}

final class _RecordingTelemetryObserver implements DioTelemetryObserver {
  final List<DioTelemetryEvent> events = <DioTelemetryEvent>[];

  @override
  void onEvent(DioTelemetryEvent event) => events.add(event);
}

final class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.inspect, this.waitFor});

  final void Function(RequestOptions options)? inspect;
  final Future<void>? waitFor;
  int closeCalls = 0;

  @override
  void close({bool force = false}) => closeCalls += 1;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    inspect?.call(options);
    if (waitFor case final wait?) await wait;
    return ResponseBody.fromString('', 204);
  }
}

final class _SentryDioInterceptor extends Interceptor {}

final class _RecordingTracer extends Tracer {
  final names = <String>[];
  final attributes = <Map<String, Object?>>[];
  final spans = <_RecordingSpan>[];

  @override
  Span startSpan(
    String name, {
    TraceContext? parent,
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {
    names.add(name);
    this.attributes.add(attributes);
    final span = _RecordingSpan(
      TraceContext(
        traceId: '0123456789abcdef0123456789abcdef',
        spanId: '0123456789abcdef',
        traceFlags: '01',
      ),
    );
    spans.add(span);
    return span;
  }
}

final class _RecordingSpan extends Span {
  _RecordingSpan(this.context);

  @override
  final TraceContext context;

  int endCalls = 0;
  SpanStatus? status;

  @override
  bool get isEnded => endCalls > 0;

  @override
  void addEvent(String name, {Map<String, Object?> attributes = const {}}) {}

  @override
  void setAttribute(String key, Object? value) {}

  @override
  void end({
    SpanStatus status = SpanStatus.unset,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (isEnded) return;
    endCalls += 1;
    this.status = status;
  }
}
