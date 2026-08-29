import 'dart:async';
import 'dart:typed_data';

import 'package:dartitect/dartitect_credentials.dart';
import 'package:dartitect_dio/dartitect_dio.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test(
    'two 401 responses clear and logout once for their generation',
    () async {
      final store = _Store('old');
      final refresher = _Refresher('new');
      final logouts = <CredentialInvalidationCause>[];
      final controller = _controller(store, refresher, logouts);
      final release = Completer<void>();
      final adapter = _Adapter((_) async {
        await release.future;
        return ResponseBody.fromString('', 401);
      });
      final dio = Dio()
        ..httpClientAdapter = adapter
        ..interceptors.add(_interceptor(controller));
      addTearDown(() async {
        dio.close(force: true);
        await controller.disposeAsync();
      });

      final first = dio.get<void>('/first');
      final second = dio.get<void>('/second');
      await adapter.started(2);
      final generations = adapter.options
          .map(
            (options) => options
                .extra[DioCredentialsInterceptor.credentialGenerationExtraKey],
          )
          .toList();
      expect(generations[0], same(generations[1]));
      release.complete();

      await expectLater(first, throwsA(isA<DioException>()));
      await expectLater(second, throwsA(isA<DioException>()));
      expect(store.clearCalls, 1);
      expect(logouts, <CredentialInvalidationCause>[
        CredentialInvalidationCause.providerRejected,
      ]);
    },
  );

  test(
    'a delayed 401 cannot invalidate a newer credential generation',
    () async {
      final store = _Store('old');
      final refresher = _Refresher('new');
      final logouts = <CredentialInvalidationCause>[];
      final controller = _controller(store, refresher, logouts);
      final release = Completer<void>();
      final adapter = _Adapter((_) async {
        await release.future;
        return ResponseBody.fromString('', 401);
      });
      final dio = Dio()
        ..httpClientAdapter = adapter
        ..interceptors.add(_interceptor(controller));
      addTearDown(() async {
        dio.close(force: true);
        await controller.disposeAsync();
      });

      final request = dio.get<void>('/delayed');
      await adapter.started(1);
      final old = controller.currentLease!;
      await controller.invalidateIfCurrent(
        old.generation,
        CredentialInvalidationCause.signOut,
      );
      final current =
          (await controller.load() as Ok<CredentialLease<String>>).value;
      expect(current.value, 'new');

      release.complete();
      await expectLater(request, throwsA(isA<DioException>()));
      expect(controller.currentLease, same(current));
      expect(store.clearCalls, 1);
      expect(logouts, <CredentialInvalidationCause>[
        CredentialInvalidationCause.signOut,
      ]);
    },
  );

  test(
    'authorized replay uses a fresh generation and happens at most once',
    () async {
      final store = _Store('old');
      final refresher = _Refresher('new');
      final logouts = <CredentialInvalidationCause>[];
      final controller = _controller(store, refresher, logouts);
      final adapter = _Adapter(
        (options) => ResponseBody.fromString(
          '',
          options.extra[DioCredentialsInterceptor
                      .credentialReplayCountExtraKey] ==
                  1
              ? 200
              : 401,
        ),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final policy = _ReplayPolicy(true);
      dio.interceptors.add(
        _interceptor(controller, retryClient: dio, replayPolicy: policy),
      );
      addTearDown(() async {
        dio.close(force: true);
        await controller.disposeAsync();
      });

      final response = await dio.get<void>('/safe');

      expect(response.statusCode, 200);
      expect(adapter.options, hasLength(2));
      expect(
        adapter.options.map((options) => options.headers['Authorization']),
        <Object?>['Bearer old', 'Bearer new'],
      );
      final firstGeneration = adapter
          .options
          .first
          .extra[DioCredentialsInterceptor.credentialGenerationExtraKey];
      final secondGeneration = adapter
          .options
          .last
          .extra[DioCredentialsInterceptor.credentialGenerationExtraKey];
      expect(secondGeneration, isNot(same(firstGeneration)));
      expect(policy.calls, 1);
      expect(store.clearCalls, 1);
      expect(logouts, hasLength(1));
    },
  );

  test(
    'policy denial does not replay and a second 401 cannot retry again',
    () async {
      Future<(int, int)> run(bool allowed) async {
        final controller = _controller(
          _Store('old'),
          _Refresher('new'),
          <CredentialInvalidationCause>[],
        );
        final adapter = _Adapter((_) => ResponseBody.fromString('', 401));
        final dio = Dio()..httpClientAdapter = adapter;
        final policy = _ReplayPolicy(allowed);
        dio.interceptors.add(
          _interceptor(controller, retryClient: dio, replayPolicy: policy),
        );
        try {
          await expectLater(
            dio.get<void>('/always-rejected'),
            throwsA(isA<DioException>()),
          );
          return (adapter.options.length, policy.calls);
        } finally {
          dio.close(force: true);
          await controller.disposeAsync();
        }
      }

      expect(await run(false), (1, 1));
      expect(await run(true), (2, 1));
    },
  );

  test('replay requires policy and never repeats streams', () async {
    final invalidController = _controller(
      _Store('old'),
      _Refresher('new'),
      <CredentialInvalidationCause>[],
    );
    final invalidDio = Dio();
    expect(
      () => DioCredentialsInterceptor<String, _Failure>(
        credentials: invalidController,
        encodeAuthorization: (value) => value,
        retryClient: invalidDio,
      ),
      throwsArgumentError,
    );
    invalidDio.close(force: true);
    await invalidController.disposeAsync();

    final store = _Store('old');
    final controller = _controller(
      store,
      _Refresher('new'),
      <CredentialInvalidationCause>[],
    );
    final adapter = _Adapter((_) => ResponseBody.fromString('', 401));
    final dio = Dio()..httpClientAdapter = adapter;
    final policy = _ReplayPolicy(true);
    dio.interceptors.add(
      _interceptor(controller, retryClient: dio, replayPolicy: policy),
    );
    addTearDown(() async {
      dio.close(force: true);
      await controller.disposeAsync();
    });

    await expectLater(
      dio.post<void>(
        '/upload',
        data: Stream<List<int>>.fromIterable(<List<int>>[
          <int>[1, 2, 3],
        ]),
      ),
      throwsA(isA<DioException>()),
    );
    expect(adapter.options, hasLength(1));
    expect(policy.calls, 0);
  });

  test(
    'CancelToken cancels one request without cancelling shared refresh',
    () async {
      final store = _Store(null);
      final refresher = _Refresher.pending();
      final controller = _controller(
        store,
        refresher,
        <CredentialInvalidationCause>[],
      );
      final adapter = _Adapter((_) => ResponseBody.fromString('', 200));
      final dio = Dio()
        ..httpClientAdapter = adapter
        ..interceptors.add(_interceptor(controller));
      addTearDown(() async {
        dio.close(force: true);
        await controller.disposeAsync();
      });
      final token = CancelToken();

      final request = dio.get<void>('/cancel', cancelToken: token);
      await _waitUntil(() => refresher.cancellation != null);
      token.cancel('caller left');
      await expectLater(
        request,
        throwsA(
          isA<DioException>().having(CancelToken.isCancel, 'cancel', isTrue),
        ),
      );
      expect(refresher.cancellation?.isCancelled, isFalse);

      refresher.complete('new');
      await _waitUntil(() => store.value?.value == 'new');
      final response = await dio.get<void>('/next');
      expect(response.statusCode, 200);
      expect(adapter.options, hasLength(1));
    },
  );
}

DioCredentialsInterceptor<String, _Failure> _interceptor(
  CredentialsController<String, _Failure> controller, {
  Dio? retryClient,
  DioCredentialReplayPolicy? replayPolicy,
}) => DioCredentialsInterceptor<String, _Failure>(
  credentials: controller,
  encodeAuthorization: (value) => 'Bearer $value',
  retryClient: retryClient,
  replayPolicy: replayPolicy,
);

CredentialsController<String, _Failure> _controller(
  _Store store,
  _Refresher refresher,
  List<CredentialInvalidationCause> logouts,
) => CredentialsController<String, _Failure>(
  store: store,
  refresher: refresher,
  now: () => DateTime.utc(2026),
  forcedLogout: (cause, _) => logouts.add(cause),
);

final class _Failure {
  const _Failure();
}

final class _Store implements CredentialStore<String, _Failure> {
  _Store(String? value)
    : value = value == null ? null : CredentialRecord<String>(value: value);

  CredentialRecord<String>? value;
  var clearCalls = 0;

  @override
  Future<Result<void, _Failure>> clear(CancellationSignal cancellation) async {
    cancellation.throwIfCancelled();
    clearCalls += 1;
    value = null;
    return const Ok<void>(null);
  }

  @override
  Future<Result<CredentialRecord<String>?, _Failure>> read(
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    return Ok<CredentialRecord<String>?>(value);
  }

  @override
  Future<Result<void, _Failure>> write(
    CredentialRecord<String> credential,
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    value = credential;
    return const Ok<void>(null);
  }
}

final class _Refresher implements CredentialRefresher<String, _Failure> {
  _Refresher(String value)
    : _result = Future.value(
        Ok<CredentialRecord<String>>(CredentialRecord<String>(value: value)),
      );

  _Refresher.pending()
    : _result = Completer<Result<CredentialRecord<String>, _Failure>>().future {
    _pending = Completer<Result<CredentialRecord<String>, _Failure>>();
    _result = _pending!.future;
  }

  late Future<Result<CredentialRecord<String>, _Failure>> _result;
  Completer<Result<CredentialRecord<String>, _Failure>>? _pending;
  CancellationSignal? cancellation;

  void complete(String value) => _pending!.complete(
    Ok<CredentialRecord<String>>(CredentialRecord<String>(value: value)),
  );

  @override
  Future<Result<CredentialRecord<String>, _Failure>> refresh(
    CredentialRecord<String>? previous,
    CancellationSignal cancellation,
  ) {
    this.cancellation = cancellation;
    cancellation.throwIfCancelled();
    return _result;
  }
}

final class _ReplayPolicy implements DioCredentialReplayPolicy {
  _ReplayPolicy(this.allowed);

  final bool allowed;
  var calls = 0;

  @override
  bool allowsReplay(RequestOptions request) {
    calls += 1;
    return allowed;
  }
}

final class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final FutureOr<ResponseBody> Function(RequestOptions options) respond;
  final options = <RequestOptions>[];

  Future<void> started(int count) => _waitUntil(() => options.length >= count);

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    this.options.add(options);
    return respond(options);
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt += 1) {
    await _flush();
  }
  if (!condition()) throw StateError('Timed out waiting for test condition.');
}
