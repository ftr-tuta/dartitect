import 'package:dartitect_dio/dartitect_dio.dart';
import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:dio/dio.dart' show RequestInterceptorHandler;
import 'package:test/test.dart';

void main() {
  test(
    '1.0 instrumentation observes metadata without reading payloads',
    () async {
      final payload = _UnreadablePayload();
      final tracer = _RecordingTracer();
      final dio = Dio();
      final instrumentation = DioInstrumentation.attach(
        dio,
        tracer: tracer,
        routeTemplate: (_) => RouteTemplate('/accounts/:accountId'),
      );
      final options = RequestOptions(
        path: 'https://example.invalid/accounts/private-account',
        method: 'POST',
        data: payload,
        queryParameters: <String, Object?>{'token': 'private-token'},
      );

      instrumentation.onRequest(options, RequestInterceptorHandler());

      expect(identical(options.data, payload), isTrue);
      expect(payload.toStringCalls, 0);
      expect(tracer.names, <String>['HTTP POST /accounts/:accountId']);
      expect(tracer.attributes.single, <String, Object?>{
        'http.request.method': 'POST',
        'http.route': '/accounts/:accountId',
      });
      expect('${tracer.attributes}', isNot(contains('private-account')));
      expect('${tracer.attributes}', isNot(contains('private-token')));

      instrumentation.dispose();
      dio.close();
    },
  );
}

final class _UnreadablePayload {
  int toStringCalls = 0;

  @override
  String toString() {
    toStringCalls += 1;
    throw StateError('payload must not be projected');
  }
}

final class _RecordingTracer extends Tracer {
  final names = <String>[];
  final attributes = <Map<String, Object?>>[];

  @override
  Span startSpan(
    String name, {
    TraceContext? parent,
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {
    names.add(name);
    this.attributes.add(attributes);
    return NoOpTracer().startSpan(name, parent: parent, kind: kind);
  }
}
