import 'package:dartitect/dartitect.dart';
import 'package:dartitect_resilience/dartitect_resilience.dart';
import 'package:dio/dio.dart';

import 'retry_after.dart';

/// Expected, payload-free Dio failure.
sealed class DioFailure implements Exception {
  const DioFailure(this.message, this.type);

  /// Stable classification message without URI, headers, or body.
  final String message;

  /// Original Dio category.
  final DioExceptionType type;

  @override
  String toString() => '$runtimeType: $message';
}

/// Request cancelled cooperatively.
final class DioCancelledFailure extends DioFailure {
  /// Creates a cancellation failure without retaining request data.
  const DioCancelledFailure()
    : super('Request cancelled.', DioExceptionType.cancel);
}

/// Absolute request deadline elapsed before a terminal response.
final class DioDeadlineExceededFailure extends DioFailure {
  /// Creates a payload-free failure retaining only the configured UTC bound.
  const DioDeadlineExceededFailure({required this.deadline})
    : super('HTTP request deadline exceeded.', DioExceptionType.receiveTimeout);

  /// Configured UTC deadline.
  final DateTime deadline;
}

/// DNS, socket, certificate, or timeout failure.
final class DioTransportFailure extends DioFailure {
  /// Creates a transport failure with a safe [message] and Dio [type].
  const DioTransportFailure(super.message, super.type);
}

/// HTTP response outside the accepted status policy.
final class DioHttpFailure extends DioFailure {
  /// Creates a response failure with status and optional typed retry feedback.
  const DioHttpFailure({required this.statusCode, this.retryAfter})
    : super('HTTP request failed.', DioExceptionType.badResponse);

  /// Response status; response headers and body are intentionally omitted.
  final int? statusCode;

  /// Opt-in bounded retry metadata, without the original response headers.
  final RetryAfterHint? retryAfter;
}

/// Invalid client/interceptor/request configuration.
final class DioConfigurationFailure extends DioFailure {
  /// Creates a client configuration failure named by safe [causeType].
  const DioConfigurationFailure({required this.causeType})
    : super('Dio request configuration failed.', DioExceptionType.unknown);

  /// Runtime type of the safe-to-name cause, never its value.
  final String causeType;
}

/// Consumer decoder rejected an otherwise accepted response payload.
final class DioDecodingFailure extends DioFailure {
  /// Creates a payload-free decoder failure.
  const DioDecodingFailure({required this.causeType})
    : super('HTTP response decoding failed.', DioExceptionType.unknown);

  /// Runtime type of the thrown decoder cause, never its message or payload.
  final String causeType;
}

/// Declared route parameters do not match the validated template.
final class DioRouteFailure extends DioFailure {
  /// Creates a safe route-configuration failure.
  const DioRouteFailure(String message)
    : super(message, DioExceptionType.unknown);
}

/// Captures only [DioException] as a typed, payload-free failure.
///
/// Programming errors and other exceptions continue to throw.
Future<Result<T, DioFailure>> captureDioException<T>(
  Future<T> Function() request, {
  DioRetryAfterPolicy? retryAfter,
}) async {
  try {
    return Ok<T>(await request());
  } on DioException catch (error, stackTrace) {
    final failure = switch (error.type) {
      DioExceptionType.cancel => const DioCancelledFailure(),
      DioExceptionType.badResponse => DioHttpFailure(
        statusCode: error.response?.statusCode,
        retryAfter: error.response == null
            ? null
            : retryAfter?.extract(error.response!.headers),
      ),
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout ||
      DioExceptionType.badCertificate ||
      DioExceptionType.connectionError => DioTransportFailure(
        'HTTP transport failed.',
        error.type,
      ),
      DioExceptionType.unknown => DioConfigurationFailure(
        causeType: error.error?.runtimeType.toString() ?? 'unknown',
      ),
    };
    return Err<DioFailure>(failure, stackTrace);
  }
}
