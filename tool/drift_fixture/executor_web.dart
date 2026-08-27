import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// Open executor plus the fixed storage capability reported by the platform.
final class DriftFixtureExecutor {
  /// Creates fixture executor metadata.
  const DriftFixtureExecutor({
    required this.executor,
    required this.storageImplementation,
    this.missingFeatures = const <String>[],
  });

  /// Consumer-owned executor passed to the generated database.
  final QueryExecutor executor;

  /// Closed platform storage implementation name.
  final String storageImplementation;

  /// Closed capability names reported by the web probe.
  final List<String> missingFeatures;
}

/// Opens Drift Web with app-provided asset URIs and database naming policy.
Future<DriftFixtureExecutor> openDriftFixtureExecutor({
  required String databaseName,
  required Uri databaseUri,
  required Uri sqlite3Uri,
  required Uri workerUri,
}) async {
  final result = await WasmDatabase.open(
    databaseName: databaseName,
    sqlite3Uri: sqlite3Uri,
    driftWorkerUri: workerUri,
  );
  return DriftFixtureExecutor(
    executor: result.resolvedExecutor,
    storageImplementation: result.chosenImplementation.name,
    missingFeatures: <String>[
      for (final feature in result.missingFeatures) feature.name,
    ],
  );
}
