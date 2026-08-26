import 'package:dartitect/dartitect.dart';
import 'package:objectbox/objectbox.dart';

/// Synchronous write transaction over a borrowed ObjectBox [Store].
///
/// Consumer code writes its domain entity and outbox entity inside [run]. An
/// expected `Err<F>` aborts both writes and is returned unchanged. Unexpected
/// exceptions also roll back and are rethrown by ObjectBox.
final class ObjectBoxMutationTransaction {
  /// Creates a transaction helper without taking ownership of [store].
  const ObjectBoxMutationTransaction(this.store);

  /// Borrowed consumer-configured Store.
  final Store store;

  /// Runs [transaction] atomically in ObjectBox write mode.
  Result<R, F> run<R, F extends Object>(
    Result<R, F> Function(Store store) transaction,
  ) {
    try {
      return store.runInTransaction<Result<R, F>>(TxMode.write, () {
        final result = transaction(store);
        if (result case Err<Object>()) {
          throw _ExpectedObjectBoxRollback(result);
        }
        return result;
      });
    } on _ExpectedObjectBoxRollback catch (rollback) {
      return rollback.result as Result<R, F>;
    }
  }
}

final class _ExpectedObjectBoxRollback implements Exception {
  const _ExpectedObjectBoxRollback(this.result);

  final Object result;
}
