import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test(
    'progressive scan emits 32 deterministic files and reuses facts',
    () async {
      const fileCount = 32;
      final root = await Directory.systemTemp.createTemp(
        'dartitect-incremental-scan-benchmark-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      await File('${root.path}/pubspec.yaml').writeAsString('''name: benchmark
environment:
  sdk: ^3.13.0
''');
      for (var index = 0; index < fileCount; index++) {
        final file = File('${root.path}/lib/file_$index.dart');
        await file.parent.create(recursive: true);
        await file.writeAsString('final value$index = $index;\n');
      }

      final sourceIndex = ProjectSourceIndex(capacity: 2048);
      final coldWatch = Stopwatch()..start();
      final cold = await _scan(root, sourceIndex);
      coldWatch.stop();
      final warmWatch = Stopwatch()..start();
      final warm = await _scan(root, sourceIndex);
      warmWatch.stop();

      expect(cold.paths, orderedEquals(warm.paths));
      expect(cold.paths, hasLength(fileCount));
      expect(cold.cacheHits, 0);
      expect(warm.cacheHits, fileCount);
      expect(cold.scan.dartFileCount, fileCount);
      expect(warm.scan.dartFileCount, fileCount);
      stdout.writeln(
        jsonEncode(<String, Object?>{
          'benchmark': 'incremental-cli-scan',
          'metrics': 'informative',
          'files': fileCount,
          'coldTotalMicros': coldWatch.elapsedMicroseconds,
          'warmTotalMicros': warmWatch.elapsedMicroseconds,
          'warmCacheHits': warm.cacheHits,
        }),
      );
    },
  );
}

Future<_ScanSample> _scan(
  Directory root,
  ProjectSourceIndex sourceIndex,
) async {
  final paths = <String>[];
  var cacheHits = 0;
  ProjectScan? completed;
  await for (final event in ProjectScanner(
    root,
    sourceIndex: sourceIndex,
  ).scanEvents()) {
    switch (event) {
      case ProjectScanFileAnalyzed(:final path, :final cacheHit):
        paths.add(path);
        if (cacheHit) cacheHits += 1;
      case ProjectScanCompleted(:final scan):
        completed = scan;
      case ProjectScanStarted() ||
          ProjectScanFileDiscovered() ||
          ProjectScanFinding() ||
          ProjectScanCancelled():
        break;
    }
  }
  return _ScanSample(paths, cacheHits, completed!);
}

final class _ScanSample {
  const _ScanSample(this.paths, this.cacheHits, this.scan);

  final List<String> paths;
  final int cacheHits;
  final ProjectScan scan;
}
