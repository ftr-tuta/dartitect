import 'dart:async';

import 'package:dartitect/dartitect.dart';

/// Recorded public-boundary evidence from one effect-channel exercise.
final class EffectHarnessResult<E extends Object, P> {
  /// Creates an immutable effect harness result.
  const EffectHarnessResult({
    required this.publishResults,
    required this.delivered,
    required this.secondConsumerRejected,
    required this.postDisposeResult,
    required this.disposeAttempted,
  });

  /// Result of each pre-listener publish in input order.
  final List<P> publishResults;

  /// Effects delivered through the only consumer in FIFO order.
  final List<E> delivered;

  /// Whether attaching a second logical consumer failed explicitly.
  final bool secondConsumerRejected;

  /// Result of emission after channel disposal began.
  final P postDisposeResult;

  /// Whether the harness attempted channel cleanup.
  final bool disposeAttempted;
}

/// Framework-neutral harness for a bounded, single-consumer effect channel.
///
/// A Flutter consumer adapts `EffectChannel.listen`, `sink.emit`, and
/// `disposeAsync` into these public callbacks; this package never imports
/// Flutter or private implementation details.
final class EffectContractHarness<E extends Object, P> {
  /// Creates an effect harness with an injected deterministic [drain].
  const EffectContractHarness({
    required this.emit,
    required this.listen,
    required this.dispose,
    this.drain = _drainMicrotasks,
  });

  /// Publishes one effect and returns its explicit acceptance result.
  final P Function(E effect) emit;

  /// Attaches the only logical consumer and returns its registration.
  final Disposable Function(FutureOr<void> Function(E effect) onEffect) listen;

  /// Closes the channel and drains any active callback.
  final FutureOr<void> Function() dispose;

  /// Deterministic scheduler drain used after attachment.
  final Future<void> Function() drain;

  /// Emits [beforeListener], attaches once, probes a second attach, then closes.
  Future<EffectHarnessResult<E, P>> run({
    required Iterable<E> beforeListener,
    required E postDisposeEffect,
  }) async {
    final publishResults = <P>[];
    final delivered = <E>[];
    Disposable? subscription;
    var secondConsumerRejected = false;
    try {
      for (final effect in beforeListener) {
        publishResults.add(emit(effect));
      }
      subscription = listen((effect) => delivered.add(effect));
      try {
        final unexpected = listen((_) {});
        unexpected.dispose();
      } on Object {
        secondConsumerRejected = true;
      }
      await drain();
    } finally {
      subscription?.dispose();
      await dispose();
    }
    return EffectHarnessResult<E, P>(
      publishResults: List<P>.unmodifiable(publishResults),
      delivered: List<E>.unmodifiable(delivered),
      secondConsumerRejected: secondConsumerRejected,
      postDisposeResult: emit(postDisposeEffect),
      disposeAttempted: true,
    );
  }
}

Future<void> _drainMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
}
