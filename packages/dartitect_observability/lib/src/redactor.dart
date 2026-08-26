/// Structural limits applied before any observability destination receives data.
final class RedactionLimits {
  /// Creates conservative limits.
  const RedactionLimits({
    this.maxDepth = 6,
    this.maxCollectionLength = 50,
    this.maxStringLength = 1024,
    this.maxAttributes = 64,
  });

  /// Maximum nested map/list depth.
  final int maxDepth;

  /// Maximum entries retained from one map or iterable.
  final int maxCollectionLength;

  /// Maximum characters retained from one string.
  final int maxStringLength;

  /// Maximum top-level attributes retained on an event.
  final int maxAttributes;
}

/// An error representation safe to pass to logs and remote reporters.
final class RedactedError implements Exception {
  /// Creates a redacted error.
  const RedactedError({required this.type, required this.message});

  /// Original runtime type, which is not user data.
  final String type;

  /// Sanitized and bounded message.
  final String message;

  @override
  String toString() => '$type: $message';
}

/// Removes common credentials and identifiers and bounds recursive metadata.
///
/// Unknown object instances are represented by their type instead of invoking
/// arbitrary `toString` implementations that may expose secrets.
final class Redactor {
  /// Creates a strict redactor.
  const Redactor({this.limits = const RedactionLimits()});

  /// Structural limits.
  final RedactionLimits limits;

  /// Sanitizes event attributes and enforces top-level cardinality.
  Map<String, Object?> sanitizeAttributes(Map<String, Object?> attributes) {
    final output = <String, Object?>{};
    for (final entry in attributes.entries.take(limits.maxAttributes)) {
      output[entry.key] = sanitize(entry.value, key: entry.key);
    }
    if (attributes.length > limits.maxAttributes) {
      output['_truncated_attributes'] =
          attributes.length - limits.maxAttributes;
    }
    return Map<String, Object?>.unmodifiable(output);
  }

  /// Sanitizes an arbitrary supported value.
  Object? sanitize(Object? value, {String? key}) =>
      _sanitize(value, key: key, depth: 0);

  /// Sanitizes an exception without retaining the original object.
  RedactedError sanitizeError(Object error) => RedactedError(
    type: error.runtimeType.toString(),
    message: _sanitizeString(error.toString()),
  );

  /// Removes absolute file locations and bounds a stack before dispatch.
  StackTrace sanitizeStackTrace(StackTrace stackTrace) => StackTrace.fromString(
    _sanitizeString(
      stackTrace.toString().replaceAll(
        RegExp(r'file:///[^\s)]+'),
        'file:///[REDACTED_PATH]',
      ),
    ),
  );

  Object? _sanitize(Object? value, {String? key, required int depth}) {
    if (_isSensitiveKey(key)) return '[REDACTED]';
    if (depth >= limits.maxDepth) return '[MAX_DEPTH]';
    if (value == null || value is bool || value is num) return value;
    if (value is String) return _sanitizeString(value);
    if (value is Uri) return sanitizeUri(value).toString();
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Duration) return value.inMicroseconds;
    if (value is Map<Object?, Object?>) {
      final output = <String, Object?>{};
      for (final entry in value.entries.take(limits.maxCollectionLength)) {
        final mapKey = _sanitizeString('${entry.key}');
        output[mapKey] = _sanitize(entry.value, key: mapKey, depth: depth + 1);
      }
      if (value.length > limits.maxCollectionLength) {
        output['_truncated_entries'] =
            value.length - limits.maxCollectionLength;
      }
      return output;
    }
    if (value is Iterable<Object?>) {
      final output = <Object?>[];
      final iterator = value.iterator;
      while (output.length < limits.maxCollectionLength &&
          iterator.moveNext()) {
        output.add(_sanitize(iterator.current, depth: depth + 1));
      }
      if (iterator.moveNext()) output.add('[TRUNCATED]');
      return output;
    }
    return '[${value.runtimeType}]';
  }

  /// Removes user-info, query, fragment, and identifying path segments.
  Uri sanitizeUri(Uri uri) => Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    pathSegments: <String>[
      for (var index = 0; index < uri.pathSegments.length; index += 1)
        if (uri.pathSegments[index].isEmpty) '' else ':segment',
    ],
  );

  bool _isSensitiveKey(String? key) =>
      key != null && _sensitiveKey.hasMatch(key);

  String _sanitizeString(String input) {
    var output = input
        .replaceAll(_jwt, '[REDACTED_JWT]')
        .replaceAll(_email, '[REDACTED_EMAIL]')
        .replaceAll(_cpf, '[REDACTED_CPF]')
        .replaceAll(_uuid, '[REDACTED_UUID]')
        .replaceAll(_authorizationValue, r'$1[REDACTED]')
        .replaceAll(_secretAssignment, r'$1[REDACTED]')
        .replaceAll(_query, '?[REDACTED_QUERY]');
    if (output.length > limits.maxStringLength) {
      output = '${output.substring(0, limits.maxStringLength)}…[TRUNCATED]';
    }
    return output;
  }

  static final RegExp _sensitiveKey = RegExp(
    r'(authorization|cookie|token|password|passwd|secret|api[_-]?key|credential|session|jwt|cpf|email|body|payload|headers?|query)',
    caseSensitive: false,
  );
  static final RegExp _jwt = RegExp(
    r'\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}(?:\.[A-Za-z0-9_-]{4,})?\b',
  );
  static final RegExp _email = RegExp(
    r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
    caseSensitive: false,
  );
  static final RegExp _cpf = RegExp(r'\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b');
  static final RegExp _uuid = RegExp(
    r'\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b',
    caseSensitive: false,
  );
  static final RegExp _authorizationValue = RegExp(
    r'\b(authorization\s*[:=]\s*|bearer\s+|basic\s+)[^\s,;]+',
    caseSensitive: false,
  );
  static final RegExp _secretAssignment = RegExp(
    r'\b((?:token|password|passwd|secret|api[_-]?key|cookie)\s*[:=]\s*)[^\s,;]+',
    caseSensitive: false,
  );
  static final RegExp _query = RegExp(r'\?[^\s#]+');
}
