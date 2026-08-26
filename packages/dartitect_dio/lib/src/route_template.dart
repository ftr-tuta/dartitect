import 'package:dartitect/dartitect.dart';
import 'package:dio/dio.dart';

/// Invalid consumer-supplied HTTP route template.
final class InvalidRouteTemplateException implements Exception {
  /// Creates a safe validation error.
  const InvalidRouteTemplateException(this.message);

  /// Safe diagnostic without the rejected input.
  final String message;

  @override
  String toString() => 'InvalidRouteTemplateException: $message';
}

/// Validated static route template safe for telemetry.
///
/// Templates are consumer-supplied metadata, never derived from the request
/// URI. Dynamic segments must use colon-name or brace-name notation.
final class RouteTemplate extends ValueEquality {
  /// Validates and creates a route template.
  factory RouteTemplate(String value) {
    if (value.isEmpty || value.length > 200 || !value.startsWith('/')) {
      throw const InvalidRouteTemplateException(
        'A route template must start with / and contain at most 200 characters.',
      );
    }
    if (value.contains(RegExp(r'[?#%\\\s]')) || value.contains('://')) {
      throw const InvalidRouteTemplateException(
        'A route template cannot contain URL, query, fragment, escape, or whitespace data.',
      );
    }
    for (final segment in value.split('/').skip(1)) {
      if (segment.isEmpty) continue;
      final staticSegment = RegExp(r'^[A-Za-z][A-Za-z0-9_-]*$');
      final colonParameter = RegExp(r'^:[A-Za-z][A-Za-z0-9_]*$');
      final braceParameter = RegExp(r'^\{[A-Za-z][A-Za-z0-9_]*\}$');
      if (!staticSegment.hasMatch(segment) &&
          !colonParameter.hasMatch(segment) &&
          !braceParameter.hasMatch(segment)) {
        throw const InvalidRouteTemplateException(
          'Dynamic route values must be represented by named placeholders.',
        );
      }
    }
    return RouteTemplate._(value);
  }

  const RouteTemplate._(this.value);

  /// Canonical safe template.
  final String value;

  @override
  Iterable<Object?> get equalityFields => <Object?>[value];

  @override
  String toString() => value;
}

/// Resolves predeclared route metadata for a request.
typedef RouteTemplateResolver = RouteTemplate? Function(RequestOptions options);
