import 'dart:async';

import 'package:dartitect/dartitect.dart';

/// Rejected creation of another distinct in-flight key.
final class SingleFlightCapacityException implements Exception {
  /// Creates a capacity rejection.
  const SingleFlightCapacityException(this.maxKeys);

  /// Configured distinct-key bound.
  final int maxKeys;
}

/// A cancelled shared operation is draining and cannot be rejoined.
final class SingleFlightDrainingException implements Exception {
  /// Creates a draining rejection.
  const SingleFlightDrainingException();
}

/// Shares one operation per equal key with independently cancellable waiters.
final class SingleFlight<K, V> implements AsyncDisposable {
  /// Creates a single-flight owner with a distinct [maxKeys] bound.
  SingleFlight({this.maxKeys = 64}) {
    if (maxKeys <= 0) {
      throw ArgumentError.value(maxKeys, 'maxKeys', 'Must be positive.');
    }
  }

  /// Maximum simultaneous distinct keys.
  final int maxKeys;

  final Map<K, _Flight<V>> _flights = <K, _Flight<V>>{};
  var _disposed = false;
  Future<void>? _disposal;

  /// Number of shared operations not yet drained.
  int get inFlightCount => _flights.length;

  /// Runs or joins [operation] for [key].
  Future<V> run(
    K key,
    Future<V> Function(CancellationSignal cancellation) operation, {
    CancellationSignal? cancellation,
  }) {
    if (_disposed) throw StateError('SingleFlight is disposed.');
    cancellation?.throwIfCancelled();
    var flight = _flights[key];
    if (flight != null && flight.source.signal.isCancelled) {
      throw const SingleFlightDrainingException();
    }
    if (flight == null) {
      if (_flights.length >= maxKeys) {
        throw SingleFlightCapacityException(maxKeys);
      }
      flight = _Flight<V>();
      _flights[key] = flight;
      flight.work = _run(key, flight, operation);
    }
    return _join(flight, cancellation);
  }

  Future<V> _run(
    K key,
    _Flight<V> flight,
    Future<V> Function(CancellationSignal cancellation) operation,
  ) async {
    try {
      return await operation(flight.source.signal);
    } finally {
      flight.completed = true;
      if (identical(_flights[key], flight)) _flights.remove(key);
      flight.source.dispose();
    }
  }

  Future<V> _join(_Flight<V> flight, CancellationSignal? cancellation) {
    final completer = Completer<V>();
    var detached = false;
    CancellationRegistration? registration;
    flight.waiterCount += 1;

    void detach() {
      if (detached) return;
      detached = true;
      registration?.dispose();
      flight.waiterCount -= 1;
      if (flight.waiterCount == 0 && !flight.completed) {
        flight.source.cancel('SingleFlight has no waiters');
      }
    }

    registration = cancellation?.register((reason) {
      if (!completer.isCompleted) {
        completer.completeError(CancellationException(reason));
      }
      detach();
    });
    unawaited(
      flight.work.then<void>(
        (value) {
          if (!completer.isCompleted) completer.complete(value);
          detach();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
          detach();
        },
      ),
    );
    return completer.future;
  }

  /// Cancels and drains every shared operation.
  @override
  Future<void> disposeAsync() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    final flights = _flights.values.toList(growable: false);
    for (final flight in flights) {
      flight.source.cancel('SingleFlight disposed');
    }
    await Future.wait<void>(
      flights.map(
        (flight) => flight.work.then<void>((_) {}, onError: (_, _) {}),
      ),
    );
    _flights.clear();
  }
}

final class _Flight<V> {
  final CancellationSource source = CancellationSource();
  late Future<V> work;
  var waiterCount = 0;
  var completed = false;
}
