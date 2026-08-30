// GENERATED CODE - DO NOT EDIT BY HAND.
// ignore_for_file: public_member_api_docs

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_dio/dartitect_dio.dart';

/// Owned Dio client with deadlines, typed failures, tracing hooks, and cancellation.
final class CacheSession2DioModule implements Disposable {
  CacheSession2DioModule._(this.owner, this.client);

  factory CacheSession2DioModule.create({
    required Duration connectTimeout,
    required Duration receiveTimeout,
    Iterable<Interceptor> interceptors = const <Interceptor>[],
  }) {
    final owner = DioOwner.create(
      options: BaseOptions(
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
      ),
      interceptors: interceptors,
    );
    return CacheSession2DioModule._(owner, DefaultDioJsonClient(owner.dio));
  }

  final DioOwner owner;
  final DioJsonClient client;

  CancelToken cancellation(CancellationSignal signal) =>
      bindCancelToken(signal);

  @override
  void dispose() => owner.dispose();
}
