import 'package:dartitect/dartitect.dart';
import 'package:dio/dio.dart';

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

/// DNS, socket, certificate, or timeout failure.
final class DioTransportFailure extends DioFailure {
  /// Creates a transport failure with a safe [message] and Dio [type].
  const DioTransportFailure(super.message, super.type);
}

/// HTTP response outside the accepted status policy.
final class DioHttpFailure extends DioFailure {
  /// Creates a response failure containing only its [statusCode].
  const DioHttpFailure({required this.statusCode})
    : super('HTTP request failed.', DioExceptionType.badResponse);

  /// Response status; response headers and body are intentionally omitted.
  final int? statusCode;
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
  Future<T> Function() request,
) async {
  try {
    return Ok<T>(await request());
  } on DioException catch (error, stackTrace) {
    final failure = switch (error.type) {
      DioExceptionType.cancel => const DioCancelledFailure(),
      DioExceptionType.badResponse => DioHttpFailure(
        statusCode: error.response?.statusCode,
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
