import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';

Future<void> main() async {
  final report = await DartitectWiringService(Directory.current).inspect();
  if (report.plan.creates.length != 100 ||
      report.plan.updates.isNotEmpty ||
      report.plan.deletes.isNotEmpty ||
      report.plan.hasConflicts ||
      report.plan.pendingRecovery) {
    throw StateError(
      'Large preview must contain exactly 100 safe creates; '
      'creates=${report.plan.creates.length}, '
      'updates=${report.plan.updates.length}, '
      'deletes=${report.plan.deletes.length}.',
    );
  }
  final featureOutputs = report.plan.creates.where(
    (operation) =>
        operation.operation.relativePath.contains('/features/') &&
        operation.operation.relativePath.contains('/composition/') &&
        !operation.operation.relativePath.contains('_workmanager.'),
  );
  final harnessOutputs = report.plan.creates.where(
    (operation) => operation.operation.relativePath.endsWith(
      '_feature_harness.wiring.dartitect.g.dart',
    ),
  );
  if (featureOutputs.length != 30 || harnessOutputs.length != 30) {
    throw StateError(
      'Large preview must contain 30 feature graphs and 30 harnesses.',
    );
  }
  final config = jsonDecode(
    await File('dartitect.json').readAsString(),
  ) as Map<String, Object?>;
  final invalid = Map<String, Object?>.of(config)..['configVersion'] = 999;
  late final String inducedError;
  try {
    DartitectConfig.parse(jsonEncode(invalid));
    throw StateError('Invalid config unexpectedly compiled.');
  } on DartitectConfigException catch (error) {
    inducedError = error.toString();
  }
  if (inducedError.length >= 512) {
    throw StateError('Induced diagnostic exceeded 512 characters.');
  }
  stdout.writeln(
    'Large consumer preview: 100 managed creates, 30 feature graphs, '
    '30 harnesses, inducedDiagnosticBytes=${utf8.encode(inducedError).length}.',
  );
}
