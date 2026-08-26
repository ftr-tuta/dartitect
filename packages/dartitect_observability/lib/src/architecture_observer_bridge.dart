import 'dart:async';

import 'package:dartitect/dartitect.dart';

import 'context.dart';
import 'logging.dart';
import 'tracing.dart';

/// Converts lifecycle and command events into logs and bounded command spans.
final class ArchitectureObserverBridge
    implements ArchitectureObserver, AsyncDisposable {
  /// Creates a bridge scoped to one composition.
  ArchitectureObserverBridge({required this.logger, required this.tracer});

  /// Runtime-local logger.
  final DartitectLogger logger;

  /// Runtime-local tracer.
  final Tracer tracer;

  final Map<String, List<Span>> _activeCommands = <String, List<Span>>{};
  final Set<Future<void>> _pendingEnds = <Future<void>>{};
  bool _disposed = false;

  /// Span destination failures isolated from architecture behavior.
  int endFailureCount = 0;

  @override
  void onEvent(ArchitectureEvent event) {
    if (_disposed) return;
    final attributes = <String, Object?>{
      'architecture.kind': event.kind.name,
      'architecture.source': event.source,
      if (event.label != null) 'architecture.label': event.label,
    };
    final context = ObservabilityContext(attributes: attributes);
    switch (event.kind) {
      case ArchitectureEventKind.commandStarted:
        final key = _key(event);
        final span = tracer.startSpan(
          event.label ?? event.source,
          kind: SpanKind.internal,
          attributes: attributes,
        );
        (_activeCommands[key] ??= <Span>[]).add(span);
        logger.debug('Architecture command started.', context: context);
      case ArchitectureEventKind.commandSucceeded:
        _finish(event, SpanStatus.ok);
        logger.debug('Architecture command succeeded.', context: context);
      case ArchitectureEventKind.commandFailed:
        _finish(
          event,
          SpanStatus.error,
          error: event.error,
          stackTrace: event.stackTrace,
        );
        logger.warning('Architecture command failed.', context: context);
      case ArchitectureEventKind.commandCrashed:
        _finish(
          event,
          SpanStatus.error,
          error: event.error,
          stackTrace: event.stackTrace,
        );
        logger.error(
          'Architecture command crashed.',
          context: context,
          error: event.error,
          stackTrace: event.stackTrace,
        );
      case ArchitectureEventKind.commandRejected:
        logger.debug('Architecture command rejected.', context: context);
      case ArchitectureEventKind.resourceReleaseFailed:
        logger.error(
          'Architecture resource release failed.',
          context: context,
          error: event.error,
          stackTrace: event.stackTrace,
        );
      case ArchitectureEventKind.operationAfterDispose:
        logger.warning(
          'Architecture operation after dispose.',
          context: context,
        );
      case ArchitectureEventKind.resourceAcquired ||
          ArchitectureEventKind.resourceReleaseStarted ||
          ArchitectureEventKind.resourceReleased ||
          ArchitectureEventKind.runtimeDisposing ||
          ArchitectureEventKind.runtimeDisposed:
        logger.trace('Architecture lifecycle event.', context: context);
    }
  }

  void _finish(
    ArchitectureEvent event,
    SpanStatus status, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final key = _key(event);
    final spans = _activeCommands[key];
    if (spans == null || spans.isEmpty) return;
    final span = spans.removeLast();
    if (spans.isEmpty) _activeCommands.remove(key);
    _trackEnd(
      () => span.end(status: status, error: error, stackTrace: stackTrace),
    );
  }

  String _key(ArchitectureEvent event) =>
      '${event.source}:${event.label ?? ''}';

  @override
  Future<void> disposeAsync() async {
    if (_disposed) return;
    _disposed = true;
    final spans = <Span>[
      for (final values in _activeCommands.values) ...values,
    ];
    _activeCommands.clear();
    for (final span in spans) {
      try {
        await span.end(status: SpanStatus.cancelled);
      } on Object {
        endFailureCount += 1;
      }
    }
    await Future.wait(_pendingEnds.toList(growable: false));
  }

  void _trackEnd(FutureOr<void> Function() end) {
    late final Future<void> pending;
    pending = Future<void>.sync(end)
        .catchError((Object _, StackTrace _) {
          endFailureCount += 1;
        })
        .whenComplete(() => _pendingEnds.remove(pending));
    _pendingEnds.add(pending);
    unawaited(pending);
  }
}
