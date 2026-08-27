import 'package:dartitect/dartitect.dart';
import 'package:drift/drift.dart';

import 'drift_instrumentation.dart';

/// Asynchronous mutation transaction over a borrowed Drift database.
///
/// Consumer code writes its domain row and outbox row inside [run]. An
/// expected `Err<F>` rolls both writes back and is returned unchanged.
/// Unexpected exceptions roll back and retain their original stack trace.
final class DriftMutationTransaction<D extends GeneratedDatabase> {
  /// Creates a transaction helper without taking ownership of [database].
  const DriftMutationTransaction(this.database, {this.instrumentation});

  /// Borrowed consumer-generated database.
  final D database;

  /// Optional borrowed instrumentation.
  final DriftInstrumentation? instrumentation;

  /// Runs [transaction] atomically in Drift.
  Future<Result<R, F>> run<R, F extends Object>(
    Future<Result<R, F>> Function(D database) transaction,
  ) async {
    Future<Result<R, F>> execute() async {
      try {
        return await database.transaction<Result<R, F>>(() async {
          final result = await transaction(database);
          if (result case Err<Object>()) {
            throw _ExpectedDriftRollback(result);
          }
          return result;
        });
      } on _ExpectedDriftRollback catch (rollback) {
        return rollback.result as Result<R, F>;
      }
    }

    final tracing = instrumentation;
    return tracing == null
        ? execute()
        : tracing.trace(DriftInstrumentedOperation.transaction, execute);
  }
}

final class _ExpectedDriftRollback implements Exception {
  const _ExpectedDriftRollback(this.result);

  final Object result;
}
