import 'dart:async';
import 'dart:typed_data';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_dio/dartitect_dio.dart';
import 'package:dartitect_transfer/dartitect_transfer.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test(
    'consumer request policy controls protocol and durable offset',
    () async {
      late RequestOptions observed;
      final dio = Dio()
        ..httpClientAdapter = _Adapter((options) {
          observed = options;
          return ResponseBody.fromString('', 204);
        });
      final transport = DioTransferTransport(
        dio: dio,
        request: (client, chunk, cancellation) => client.put<Object?>(
          'https://example.invalid/assets/private-id',
          data: chunk.bytes,
          options: Options(
            headers: <String, Object?>{
              'Content-Range':
                  'bytes ${chunk.offset}-${chunk.nextOffset - 1}/*',
              'Idempotency-Key': 'consumer-owned-secret',
            },
          ),
          cancelToken: cancellation,
        ),
        decodeCommit: (_, chunk) => TransferCommit(chunk.nextOffset),
      );
      final result = await transport.transmit(
        TransferChunk(offset: 4, bytes: <int>[1, 2]),
        CancellationSource().signal,
      );

      expect((result as Ok<TransferCommit>).value.durableOffset, 6);
      expect(observed.headers['Content-Range'], 'bytes 4-5/*');
      expect(observed.headers['Idempotency-Key'], 'consumer-owned-secret');
      dio.close();
    },
  );

  test('Dio failures remain payload-free typed transfer failures', () async {
    final dio = Dio()
      ..httpClientAdapter = _Adapter(
        (_) => ResponseBody.fromString('private response', 503),
      );
    final transport = DioTransferTransport(
      dio: dio,
      request: (client, chunk, cancellation) => client.put<Object?>(
        'https://example.invalid/private/path',
        data: chunk.bytes,
        cancelToken: cancellation,
      ),
      decodeCommit: (_, chunk) => TransferCommit(chunk.nextOffset),
    );

    final result = await transport.transmit(
      TransferChunk(offset: 0, bytes: <int>[42]),
      CancellationSource().signal,
    );
    final failure = (result as Err<DioFailure>).failure;
    expect(failure, isA<DioHttpFailure>());
    expect('$failure', isNot(contains('private')));
    expect('$failure', isNot(contains('example.invalid')));
    dio.close();
  });

  test('cooperative cancellation reaches the consumer Dio request', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final dio = Dio()
      ..httpClientAdapter = _Adapter((_) async {
        started.complete();
        await release.future;
        return ResponseBody.fromString('', 204);
      });
    final transport = DioTransferTransport(
      dio: dio,
      request: (client, chunk, cancellation) => client.put<Object?>(
        'https://example.invalid/upload',
        data: chunk.bytes,
        cancelToken: cancellation,
      ),
      decodeCommit: (_, chunk) => TransferCommit(chunk.nextOffset),
    );
    final source = CancellationSource();
    final pending = transport.transmit(
      TransferChunk(offset: 0, bytes: <int>[1]),
      source.signal,
    );
    await started.future;
    source.cancel('stop');
    release.complete();
    expect(
      (await pending as Err<DioFailure>).failure,
      isA<DioCancelledFailure>(),
    );
    dio.close();
  });
}

final class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final FutureOr<ResponseBody> Function(RequestOptions options) respond;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final response = Future<ResponseBody>.value(respond(options));
    if (cancelFuture == null) return response;
    return Future.any<ResponseBody>(<Future<ResponseBody>>[
      response,
      cancelFuture.then<ResponseBody>(
        (_) => throw DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
        ),
      ),
    ]);
  }
}
