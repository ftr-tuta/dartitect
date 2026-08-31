import 'dart:async';

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

/// Request context expected a credential generation that is no longer current.
final class DioCredentialGenerationMismatch implements Exception {
  /// Creates a payload-free fencing failure.
  const DioCredentialGenerationMismatch();

  @override
  String toString() => 'DioCredentialGenerationMismatch()';
}

/// Explicit consumer policy for replaying one authenticated request.
abstract interface class DioCredentialReplayPolicy {
  /// Whether [request] is semantically idempotent and safe to replay once.
  bool allowsReplay(RequestOptions request);
}

/// Generation-aware Dio integration over a consumer-owned controller.
final class DioCredentialsInterceptor<C extends Object, F extends Object>
    extends Interceptor {
  /// Creates an interceptor without retaining an encoded header value.
  DioCredentialsInterceptor({
    required this.credentials,
    required this.encodeAuthorization,
    this.authorizationHeader = 'Authorization',
    Set<int> invalidationStatusCodes = const <int>{401},
    this.retryClient,
    this.replayPolicy,
  }) : invalidationStatusCodes = Set<int>.unmodifiable(
         invalidationStatusCodes,
       ) {
    if (authorizationHeader.trim().isEmpty) {
      throw ArgumentError.value(
        authorizationHeader,
        'authorizationHeader',
        'Must not be empty.',
      );
    }
    if (this.invalidationStatusCodes.isEmpty ||
        this.invalidationStatusCodes.any(
          (status) => status < 100 || status > 599,
        )) {
      throw ArgumentError.value(
        invalidationStatusCodes,
        'invalidationStatusCodes',
        'Must contain only valid HTTP status codes.',
      );
    }
    if ((retryClient == null) != (replayPolicy == null)) {
      throw ArgumentError(
        'retryClient and replayPolicy must be supplied together.',
      );
    }
  }

  /// Extra key carrying the exact credential generation used by a request.
  static const String credentialGenerationExtraKey =
      'dartitect.credentials.generation';

  /// Extra key fencing authenticated replay to at most one attempt.
  static const String credentialReplayCountExtraKey =
      'dartitect.credentials.replayCount';

  /// Borrowed credential lifecycle controller.
  final CredentialsController<C, F> credentials;

  /// Consumer-owned credential-to-header encoding.
  final String Function(C credential) encodeAuthorization;

  /// Header receiving the encoded value.
  final String authorizationHeader;

  /// Responses that may invalidate the request's credential generation.
  final Set<int> invalidationStatusCodes;

  /// Borrowed Dio client used only when [replayPolicy] explicitly permits it.
  final Dio? retryClient;

  /// Explicit semantic idempotency/replay decision.
  final DioCredentialReplayPolicy? replayPolicy;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final expectedGeneration = options.extra[credentialGenerationExtraKey];
      final loaded = await _withCancelToken(
        credentials.load(),
        options.cancelToken,
      );
      switch (loaded) {
        case Ok<dynamic>(:final value):
          final lease = value as CredentialLease<C>;
          if (expectedGeneration is CredentialGeneration &&
              !identical(expectedGeneration, lease.generation)) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.unknown,
                error: const DioCredentialGenerationMismatch(),
              ),
            );
            return;
          }
          options.headers[authorizationHeader] = encodeAuthorization(
            lease.value,
          );
          options.extra[credentialGenerationExtraKey] = lease.generation;
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
    } on DioException catch (error) {
      handler.reject(error);
    } catch (error, stackTrace) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) async {
    final options = error.requestOptions;
    final status = error.response?.statusCode;
    final generation = options.extra[credentialGenerationExtraKey];
    if (status == null ||
        !invalidationStatusCodes.contains(status) ||
        generation is! CredentialGeneration) {
      handler.next(error);
      return;
    }

    try {
      final invalidated = await _withCancelToken(
        credentials.invalidateIfCurrent(
          generation,
          CredentialInvalidationCause.providerRejected,
        ),
        options.cancelToken,
      );
      if (invalidated case Err<F>()) {
        handler.next(error);
        return;
      }
      if (!_mayReplay(options)) {
        handler.next(error);
        return;
      }
      final replayed = await _replay(options);
      handler.resolve(replayed);
    } on DioException catch (retryError) {
      handler.next(retryError);
    } catch (retryError, stackTrace) {
      handler.next(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: retryError,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  bool _mayReplay(RequestOptions options) {
    final policy = replayPolicy;
    if (retryClient == null || policy == null) return false;
    final count = options.extra[credentialReplayCountExtraKey];
    if (count is int && count >= 1) return false;
    final data = options.data;
    if (data is Stream<dynamic> || data is FormData || data is MultipartFile) {
      return false;
    }
    return policy.allowsReplay(options);
  }

  Future<Response<dynamic>> _replay(RequestOptions options) async {
    final loaded = await _withCancelToken(
      credentials.load(),
      options.cancelToken,
    );
    final lease = switch (loaded) {
      Ok<dynamic>(:final value) => value as CredentialLease<C>,
      Err<Object>(:final failure, :final stackTrace) => throw DioException(
        requestOptions: options,
        type: DioExceptionType.unknown,
        error: DioCredentialsUnavailable<F>(failure as F, stackTrace),
        stackTrace: stackTrace,
      ),
    };
    final extra = Map<String, dynamic>.of(options.extra)
      ..[credentialGenerationExtraKey] = lease.generation
      ..[credentialReplayCountExtraKey] = 1;
    final headers = Map<String, dynamic>.of(options.headers)
      ..[authorizationHeader] = encodeAuthorization(lease.value);
    return retryClient!.fetch<dynamic>(
      options.copyWith(extra: extra, headers: headers),
    );
  }

  static Future<T> _withCancelToken<T>(
    Future<T> operation,
    CancelToken? token,
  ) {
    if (token == null) return operation;
    final cancelled = token.cancelError;
    if (cancelled != null)
      return Future<T>.error(cancelled, cancelled.stackTrace);
    final completer = Completer<T>();
    unawaited(
      token.whenCancel.then<void>((error) {
        if (!completer.isCompleted) {
          completer.completeError(error, error.stackTrace);
        }
      }),
    );
    unawaited(
      operation.then<void>(
        (value) {
          if (!completer.isCompleted) completer.complete(value);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        },
      ),
    );
    return completer.future;
  }
}
