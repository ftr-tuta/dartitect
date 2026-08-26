/// Sanitized kind of Flutter binding that completed one build.
enum FlutterBindingKind {
  /// Basic selection over a borrowed Flutter listenable.
  listenableSelector,

  /// Direct build over a borrowed Flutter value listenable.
  reactiveValue,

  /// One lifecycle-aware resource observation.
  liveResource,

  /// Structural collection observation.
  liveCollection,

  /// Paged operation and local-collection observation.
  pagedLive,
}

/// Payload-free build measurement emitted by Dartitect Flutter bindings.
///
/// Domain values, keys, queries, errors, owner tokens, routes, and user/session
/// identifiers are deliberately absent. Consumers may aggregate these fixed
/// facts without turning diagnostics into another state channel.
final class FlutterBindingBuildEvent {
  /// Creates one sanitized build event.
  const FlutterBindingBuildEvent({
    required this.kind,
    required this.buildCount,
    required this.duration,
    required this.liveHandleCount,
    required this.tickerEnabled,
  });

  /// Static binding category.
  final FlutterBindingKind kind;

  /// Monotonic build count for this widget-state generation.
  final int buildCount;

  /// Time spent in the consumer builder callback.
  final Duration duration;

  /// Number of local listener/observation handles held by this binding.
  final int liveHandleCount;

  /// Whether this build generation is actively observing its source.
  final bool tickerEnabled;
}

/// Optional, borrowed observer for sanitized binding measurements.
typedef FlutterBindingBuildObserver = void Function(
  FlutterBindingBuildEvent event,
);
