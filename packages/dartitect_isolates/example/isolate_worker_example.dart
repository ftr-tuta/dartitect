import 'package:dartitect/dartitect.dart';
import 'package:dartitect_isolates/dartitect_isolates.dart';

Future<void> main() async {
  final worker = await IsolateWorker.spawn<int, int, StateError>(
    handler: _double,
  );
  try {
    final result = await worker.execute(21, requestId: 'example');
    if (result != const Ok<int>(42)) {
      throw StateError('Unexpected worker result.');
    }
  } finally {
    await worker.safeStop();
  }
}

Future<Result<int, StateError>> _double(
  int value,
  CancellationSignal cancellation,
) async {
  cancellation.throwIfCancelled();
  return Ok<int>(value * 2);
}
