import 'package:dartitect/dartitect.dart';

import 'context.dart';
import 'logging.dart';

/// Maps payload-free reactive events to a borrowed privacy-aware logger.
///
/// The message and attribute keys are fixed. Values are limited to enums,
/// registered static causes, revisions, duration, and listener count. A
/// downstream runtime/Sentry sink sanitizes the event again before dispatch.
final class ReactiveObserverLoggerAdapter implements ReactiveObserver {
  /// Creates an adapter without taking ownership of [logger].
  const ReactiveObserverLoggerAdapter({required DartitectLogger logger})
    : _logger = logger;

  final DartitectLogger _logger;

  @override
  void onChange(ReactiveChangeEvent event) {
    _logger.debug(
      'reactive.change',
      context: ObservabilityContext(
        attributes: <String, Object?>{
          'reactive.source': event.source.name,
          'reactive.kind': event.kind.name,
          'reactive.cause_key': event.cause.key,
          'reactive.cause_label': event.cause.label,
          'reactive.previous_revision': event.previousRevision,
          'reactive.next_revision': event.nextRevision,
          'reactive.duration_us': event.duration.inMicroseconds,
          'reactive.listener_count': event.listenerCount,
        },
      ),
    );
  }
}
