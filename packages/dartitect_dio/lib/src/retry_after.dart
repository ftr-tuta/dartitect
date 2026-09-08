import 'package:dartitect_resilience/dartitect_resilience.dart';
import 'package:dio/dio.dart';

/// Opt-in extraction of bounded, payload-free Retry-After metadata from Dio.
///
/// This policy never retries a request and never retains headers or bodies.
final class DioRetryAfterPolicy {
  /// Borrows a neutral parser and a consumer-selected receipt clock.
  const DioRetryAfterPolicy({required this.parser, required this.clock});

  /// Bounded neutral field parser.
  final RetryAfterParser parser;

  /// Receipt clock; synchronization and skew correction remain consumer-owned.
  final ResilienceClock clock;

  /// Extracts one field; duplicate field lines are invalid, never joined.
  RetryAfterHint extract(Headers headers) {
    final fields = headers['retry-after'];
    if (fields == null) return const RetryAfterHint.absent();
    if (fields.length != 1) return const RetryAfterHint.invalid();
    return parser.parse(fields.single, receivedAt: clock.now().toUtc());
  }
}
