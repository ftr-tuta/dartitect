import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartitect_cli/dartitect_cli.dart';

const _featureCount = 100;
const _warmSamples = 7;
const _maxMedianMicroseconds = 2000000;

Future<void> main() async {
  final root = await Directory.systemTemp.createTemp(
    'dartitect-wiring-benchmark-',
  );
  try {
    final declarations = <String, DartitectFeatureDeclaration>{
      for (var index = 0; index < _featureCount; index += 1)
        'feature_${index.toString().padLeft(3, '0')}':
            DartitectFeatureDeclaration(
              profile: FeatureProfile.online,
              scope: index.isEven
                  ? FeatureScope.application
                  : FeatureScope.session,
              persistence: FeaturePersistenceMatrix(
                native: 'none',
                web: 'none',
              ),
              transport: 'dio',
              pagination: FeaturePagination.none,
              diagnostics: FeatureDiagnosticsLevel.basic,
              headless: <DartitectPlatform, bool>{
                for (final platform in DartitectPlatform.values)
                  platform: false,
              },
            ),
    };
    final config = DartitectConfig(
      features: DartitectFeaturesConfig(declarations: declarations),
    );
    await File('${root.path}/dartitect.json')
        .writeAsString(config.encode(), flush: true);
    final service = DartitectWiringService(root);
    final initial = await service.apply(config: config);
    if (initial.writes < _featureCount) {
      throw StateError(
        'Expected at least $_featureCount initial writes, found '
        '${initial.writes}.',
      );
    }

    final samples = <int>[];
    for (var sample = 0; sample < _warmSamples; sample += 1) {
      final stopwatch = Stopwatch()..start();
      final report = await service.inspect(config: config);
      stopwatch.stop();
      if (!report.isFresh || report.writes != 0) {
        throw StateError('Warm wiring preview was not a zero-write no-op.');
      }
      samples.add(stopwatch.elapsedMicroseconds);
    }
    samples.sort();
    final median = samples[samples.length ~/ 2];

    final before = await _treeDigests(root);
    final noOp = await service.apply(config: config);
    final after = await _treeDigests(root);
    final byteStable = const MapEquality<String, String>().equals(
      before,
      after,
    );
    final passed =
        median <= _maxMedianMicroseconds && noOp.writes == 0 && byteStable;
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'featureCount': _featureCount,
        'initialWrites': initial.writes,
        'warmSamples': _warmSamples,
        'warmMicroseconds': samples,
        'warmMedianMicroseconds': median,
        'maxWarmMedianMicroseconds': _maxMedianMicroseconds,
        'noOpWrites': noOp.writes,
        'byteStable': byteStable,
        'gate': passed ? 'PASS' : 'FAIL',
      }),
    );
    if (!passed) exitCode = 1;
  } finally {
    if (await root.exists()) await root.delete(recursive: true);
  }
}

Future<Map<String, String>> _treeDigests(Directory root) async {
  final files = <File>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is File) files.add(entity);
  }
  files.sort((left, right) => left.path.compareTo(right.path));
  return <String, String>{
    for (final file in files)
      file.path.substring(root.path.length + 1): sha256
          .convert(await file.readAsBytes())
          .toString(),
  };
}

final class MapEquality<K, V> {
  const MapEquality();

  bool equals(Map<K, V> left, Map<K, V> right) =>
      left.length == right.length &&
      left.entries.every((entry) => right[entry.key] == entry.value);
}
