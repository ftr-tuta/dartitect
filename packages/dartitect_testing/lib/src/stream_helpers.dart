import 'dart:async';

/// Waits for [count] events with an explicit timeout.
///
/// The subscription is always cancelled. A timeout message includes the
/// number of events observed so far.
Future<List<T>> collectStreamEvents<T>(
  Stream<T> stream, {
  required int count,
  required Duration timeout,
}) async {
  if (count < 0) {
    throw ArgumentError.value(count, 'count', 'must not be negative');
  }
  if (count == 0) {
    return <T>[];
  }

  final events = <T>[];
  final completer = Completer<List<T>>();
  late StreamSubscription<T> subscription;
  Timer? timer;

  subscription = stream.listen(
    (event) {
      events.add(event);
      if (events.length == count && !completer.isCompleted) {
        completer.complete(List<T>.unmodifiable(events));
      }
    },
    onError: (Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    },
    onDone: () {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(
            'Stream closed after ${events.length} of $count expected event(s).',
          ),
        );
      }
    },
  );
  timer = Timer(timeout, () {
    if (!completer.isCompleted) {
      completer.completeError(
        TimeoutException(
          'Observed ${events.length} of $count expected stream event(s).',
          timeout,
        ),
      );
    }
  });

  try {
    return await completer.future;
  } finally {
    timer.cancel();
    await subscription.cancel();
  }
}

/// Waits for the first event matching [where] with an explicit timeout.
Future<T> waitForStreamEvent<T>(
  Stream<T> stream, {
  required bool Function(T event) where,
  required Duration timeout,
}) async {
  final events = await collectStreamEvents<T>(
    stream.where(where),
    count: 1,
    timeout: timeout,
  );
  return events.single;
}
