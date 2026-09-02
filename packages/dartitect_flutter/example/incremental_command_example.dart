import 'package:dartitect_flutter/dartitect_flutter_incremental.dart';

Future<void> main() async {
  final command = IncrementalCommand<int, int, _LoadFailure, double>(
    operation: IncrementalOperation<int, _LoadFailure>.sync(() sync* {
      for (var value = 1; value <= 5; value++) {
        yield Ok<int>(value);
      }
    }),
    initialAggregate: () => 0,
    reducer: (sum, value, _) => sum + value,
    progressOf: (_, __, context) => context.sequence / 5,
    publication: IncrementalPublication.coalesceMicrotask,
  );
  try {
    await command.execute();
    final state = command.state;
    assert(
      state is IncrementalCommandSucceeded<int, _LoadFailure, double> &&
          state.aggregate == 15 &&
          state.emissionCount == 5,
    );
  } finally {
    await command.disposeAsync();
  }
}

final class _LoadFailure implements Exception {}
