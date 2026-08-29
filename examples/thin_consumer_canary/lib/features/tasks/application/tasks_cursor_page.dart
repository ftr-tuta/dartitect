import 'package:dartitect/dartitect.dart';

/// Consumer-decoded cursor page; cursors remain opaque to Dartitect.
final class TasksCursorPage<T>({
  required final List<T> items,
  required final String? nextCursor,
});

/// Consumer-owned cursor transport boundary.
abstract interface class TasksCursorReader<T, F extends Object> {
  Future<Result<TasksCursorPage<T>, F>> read({
    required String? cursor,
    required CancellationSignal cancellation,
  });
}
