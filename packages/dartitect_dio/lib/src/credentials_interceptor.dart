import 'package:dartitect/dartitect.dart';
import 'package:dartitect/dartitect_credentials.dart';
import 'package:dio/dio.dart';

/// Typed credential acquisition failure surfaced at the Dio boundary.
final class DioCredentialsUnavailable<F extends Object> implements Exception {
  /// Creates a failure preserving the consumer failure and its stack.
  const DioCredentialsUnavailable(this.failure, this.stackTrace);

  /// Consumer-owned expected credential failure.
  final F failure;

  /// Stack captured by the credential result.
  final StackTrace stackTrace;

  @override
  String toString() => 'DioCredentialsUnavailable<$F>()';
}

/// Expiry-aware Dio integration over a consumer-owned credential controller.
final class DioCredentialsInterceptor<C extends Object, F extends Object>
    extends Interceptor {
  /// Creates an interceptor without retaining an encoded header value.
  DioCredentialsInterceptor({
    required this.credentials,
    required this.encodeAuthorization,
    this.authorizationHeader = 'Authorization',
    this.invalidationStatusCodes = const <int>{401},
  });

  /// Borrowed credential lifecycle controller.
  final CredentialsController<C, F> credentials;

  /// Consumer-owned credential-to-header encoding.
  final String Function(C credential) encodeAuthorization;

  /// Header receiving the encoded value.
  final String authorizationHeader;

  /// Responses that invalidate credentials and force a session rebuild.
  final Set<int> invalidationStatusCodes;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final source = CancellationSource();
    try {
      final loaded = await credentials.load(cancellation: source.signal);
      switch (loaded) {
        case Ok<dynamic>(:final value):
          final credential = value as CredentialRecord<C>;
          options.headers[authorizationHeader] = encodeAuthorization(
            credential.value,
          );
          handler.next(options);
        case Err<Object>(:final failure, :final stackTrace):
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.unknown,
              error: DioCredentialsUnavailable<F>(failure as F, stackTrace),
              stackTrace: stackTrace,
            ),
          );
      }
    } catch (error, stackTrace) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: error,
          stackTrace: stackTrace,
        ),
      );
    } finally {
      source.dispose();
    }
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) async {
    final status = error.response?.statusCode;
    if (status != null && invalidationStatusCodes.contains(status)) {
      final source = CancellationSource();
      try {
        await credentials.invalidate(
          CredentialInvalidationCause.providerRejected,
          cancellation: source.signal,
        );
      } finally {
        source.dispose();
      }
    }
    handler.next(error);
  }
}
