import 'tracing.dart';

/// Immutable correlation and metadata carried across observability boundaries.
final class ObservabilityContext {
  /// Creates a context. Values are sanitized again before dispatch.
  ObservabilityContext({
    this.traceContext,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) : attributes = Map<String, Object?>.unmodifiable(attributes);

  /// Distributed trace identity, when tracing is enabled.
  final TraceContext? traceContext;

  /// Bounded metadata. Do not put credentials or payloads here.
  final Map<String, Object?> attributes;

  /// Returns a new context with stable merged attributes.
  ObservabilityContext merge(Map<String, Object?> additions) =>
      ObservabilityContext(
        traceContext: traceContext,
        attributes: <String, Object?>{...attributes, ...additions},
      );
}
