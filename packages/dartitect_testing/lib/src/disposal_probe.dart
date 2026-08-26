import 'dart:async';

import 'package:dartitect/dartitect.dart';

/// Records synchronous and asynchronous disposal calls and their order.
final class DisposalProbe implements Disposable, AsyncDisposable {
  /// Creates a disposal probe.
  DisposalProbe({
    this.label = 'probe',
    List<String>? order,
    this.syncError,
    this.asyncError,
    this.asyncGate,
  }) : order = order ?? <String>[];

  /// Label written to [order].
  final String label;

  /// Shared order log, useful across several probes.
  final List<String> order;

  /// Optional error thrown by [dispose].
  final Object? syncError;

  /// Optional error thrown by [disposeAsync].
  final Object? asyncError;

  /// Optional gate awaited by [disposeAsync].
  final Future<void>? asyncGate;

  /// Number of calls to [dispose].
  int disposeCalls = 0;

  /// Number of calls to [disposeAsync].
  int disposeAsyncCalls = 0;

  @override
  void dispose() {
    disposeCalls += 1;
    order.add('$label:dispose');
    final error = syncError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> disposeAsync() async {
    disposeAsyncCalls += 1;
    order.add('$label:disposeAsync');
    await asyncGate;
    final error = asyncError;
    if (error != null) {
      throw error;
    }
  }
}
