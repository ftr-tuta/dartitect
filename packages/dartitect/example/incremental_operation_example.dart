import 'package:dartitect/dartitect_incremental.dart';

Future<void> main() async {
  final operation = IncrementalOperation<int, _LoadFailure>.async(() async* {
    for (var value = 1; value <= 5; value++) {
      yield Ok<int>(value);
    }
  });

  final result = await operation.fold<int>(
    initial: 0,
    reducer: (sum, value, _) => sum + value,
  );
  switch (result.outcome) {
    case Ok<void>():
      assert(result.aggregate == 15);
      assert(result.report.emissionCount == 5);
    case Err<Object>(:final failure):
      throw StateError('Unexpected example failure: $failure');
  }
}

final class _LoadFailure implements Exception {}
