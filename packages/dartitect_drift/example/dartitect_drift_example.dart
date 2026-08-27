import 'package:dartitect/dartitect.dart';
import 'package:dartitect_drift/dartitect_drift.dart';
import 'package:drift/drift.dart';

/// Executor-neutral composition: the app supplies its generated database.
Future<Result<String, SaveFailure>>
saveWithOutbox<AppDatabase extends GeneratedDatabase>(
  AppDatabase database,
  Future<void> Function(AppDatabase database) saveDomainAndOutbox,
) =>
    DriftMutationTransaction<AppDatabase>(database)
        .run<String, SaveFailure>((borrowed) async {
          await saveDomainAndOutbox(borrowed);
          return const Ok<String>('saved');
        });

final class SaveFailure implements Exception {
  const SaveFailure();
}
