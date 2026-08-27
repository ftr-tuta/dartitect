import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

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

/// Opens a background native executor for a fixture-owned file.
Future<DriftFixtureExecutor> openDriftFixtureExecutor({
  required String databaseName,
  required Uri databaseUri,
  required Uri sqlite3Uri,
  required Uri workerUri,
}) async => DriftFixtureExecutor(
  executor: NativeDatabase.createInBackground(File.fromUri(databaseUri)),
  storageImplementation: 'nativeBackground',
);
