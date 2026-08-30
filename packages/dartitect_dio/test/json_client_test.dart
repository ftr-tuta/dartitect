import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_dio/dartitect_dio.dart';
import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  for (final method in const <String>[
    'GET',
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
  ]) {
    test(
      '$method encodes path segments and delegates query/body to Dio',
      () async {
        late RequestOptions observed;
        final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
          ..httpClientAdapter = _JsonAdapter((options) {
            observed = options;
            return ResponseBody.fromString(
              jsonEncode(<String, Object?>{'value': 42}),
              200,
              headers: <String, List<String>>{
                Headers.contentTypeHeader: <String>[Headers.jsonContentType],
              },
            );
          });
        final client = DefaultDioJsonClient(dio);
        final endpoint = DioEndpoint<int>(
          method: method,
          route: RouteTemplate('/people/:id'),
          decode: (json) => (json! as Map<String, Object?>)['value']! as int,
          acceptedStatusCodes: const <int>{200},
        );

        final result = await client.execute<int>(
          endpoint,
          pathParameters: const <String, String>{'id': 'a/b c'},
          query: const <String, Object?>{'page': 2},
          jsonBody: const <String, Object?>{'name': 'private'},
        );

        expect((result as Ok<DioResponse<int>>).value.payload, 42);
        expect(observed.method, method);
        expect(observed.path, '/people/a%2Fb%20c');
        expect(observed.queryParameters, <String, Object?>{'page': 2});
        expect(observed.data, <String, Object?>{'name': 'private'});
        dio.close();
      },
    );
  }

  test(
    'unexpected status, invalid JSON, and decoder crashes are typed',
    () async {
      Future<Result<DioResponse<int>, DioFailure>> run(
        ResponseBody Function() response,
        int Function(Object?) decode,
      ) async {
        final dio = Dio()..httpClientAdapter = _JsonAdapter((_) => response());
        addTearDown(dio.close);
        return DefaultDioJsonClient(dio).execute<int>(
          DioEndpoint<int>(
            method: 'GET',
            route: RouteTemplate('/health'),
            decode: decode,
            acceptedStatusCodes: const <int>{200},
          ),
        );
      }

      final status = await run(
        () => ResponseBody.fromString('{}', 503),
        (_) => 1,
      );
      expect((status as Err<DioFailure>).failure, isA<DioHttpFailure>());

      final invalidJson = await run(
        () => ResponseBody.fromString(
          '{',
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>[Headers.jsonContentType],
          },
        ),
        (_) => 1,
      );
      expect(
        (invalidJson as Err<DioFailure>).failure,
        isA<DioDecodingFailure>(),
      );

      final decoder = await run(
        () => ResponseBody.fromString(
          '{}',
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>[Headers.jsonContentType],
          },
        ),
        (_) => throw const FormatException('payload intentionally omitted'),
      );
      expect((decoder as Err<DioFailure>).failure, isA<DioDecodingFailure>());
      expect('${(decoder).failure}', isNot(contains('payload intentionally')));
    },
  );

  test(
    'missing parameters and cancellation before/during request are typed',
    () async {
      final release = Completer<void>();
      final started = Completer<void>();
      final dio = Dio()
        ..httpClientAdapter = _JsonAdapter((_) async {
          if (!started.isCompleted) started.complete();
          await release.future;
          return ResponseBody.fromString('{}', 200);
        });
      final client = DefaultDioJsonClient(dio);
      final endpoint = DioEndpoint<int>(
        method: 'GET',
        route: RouteTemplate('/people/:id'),
        decode: (_) => 1,
        acceptedStatusCodes: const <int>{200},
      );

      final missing = await client.execute<int>(endpoint);
      expect((missing as Err<DioFailure>).failure, isA<DioRouteFailure>());

      final before = CancellationSource()..cancel();
      final cancelledBefore = await client.execute<int>(
        endpoint,
        pathParameters: const <String, String>{'id': '1'},
        cancellation: before.signal,
      );
      expect(
        (cancelledBefore as Err<DioFailure>).failure,
        isA<DioCancelledFailure>(),
      );

      final during = CancellationSource();
      final pending = client.execute<int>(
        endpoint,
        pathParameters: const <String, String>{'id': '2'},
        cancellation: during.signal,
      );
      await started.future;
      during.cancel();
      release.complete();
      final cancelledDuring = await pending;
      expect(
        (cancelledDuring as Err<DioFailure>).failure,
        isA<DioCancelledFailure>(),
      );
      dio.close();
    },
  );

  test('status decoders and request context stay typed and bounded', () async {
    late RequestOptions observed;
    var requests = 0;
    final dio = Dio()
      ..httpClientAdapter = _JsonAdapter((options) {
        requests += 1;
        observed = options;
        return ResponseBody.fromString('{}', 404);
      });
    addTearDown(dio.close);
    final parent = TraceContext(
      traceId: '1' * 32,
      spanId: '2' * 16,
      traceFlags: '01',
    );
    final endpoint = DioEndpoint<String>(
      method: 'GET',
      route: RouteTemplate('/tasks'),
      acceptedStatusCodes: const <int>{200, 404},
      statusDecoders: <int, DioStatusDecoder<String>>{
        200: (_) => 'found',
        404: (_) => 'missing',
      },
    );

    final result = await DefaultDioJsonClient(dio).execute<String>(
      endpoint,
      headers: const <String, Object?>{'X-Mode': 'canary'},
      context: DioRequestContext(traceParent: parent),
    );

    expect((result as Ok<DioResponse<String>>).value.payload, 'missing');
    expect(observed.headers['X-Mode'], 'canary');
    expect(
      observed.extra[DioInstrumentation.parentTraceContextExtraKey],
      same(parent),
    );
    expect(requests, 1);

    final expired = await DefaultDioJsonClient(dio).execute<String>(
      endpoint,
      context: DioRequestContext(
        deadline: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
      ),
    );
    expect(
      (expired as Err<DioFailure>).failure,
      isA<DioDeadlineExceededFailure>(),
    );
    expect(requests, 1);
  });
}

final class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.respond);

  final FutureOr<ResponseBody> Function(RequestOptions options) respond;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (cancelFuture == null) return respond(options);
    return Future.any<ResponseBody>(<Future<ResponseBody>>[
      Future<ResponseBody>.value(respond(options)),
      cancelFuture.then<ResponseBody>(
        (_) => throw DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
        ),
      ),
    ]);
  }
}
