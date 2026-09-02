import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('accepts checked-in structural performance evidence', () async {
    final result = await Process.run(Platform.resolvedExecutable, <String>[
      'tool/check_flutter_quality_performance.dart',
    ]);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('flutter-quality-performance-v1 passed'));
  });

  test('rejects time or memory thresholds', () async {
    final sourceRoot = Directory.current.absolute;
    final root = await Directory.systemTemp.createTemp('flutter-quality-perf-');
    addTearDown(() => root.delete(recursive: true));
    final contract = jsonDecode(
      File('${sourceRoot.path}/tool/flutter_quality_performance_contract.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    contract['thresholds'] = <String, Object?>{
      'frameTime': 16667,
      'memory': false,
    };
    final file = File(
      '${root.path}/tool/flutter_quality_performance_contract.json',
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(contract));

    final result = await Process.run(Platform.resolvedExecutable, <String>[
      '${sourceRoot.path}/tool/check_flutter_quality_performance.dart',
      '--root=${root.path}',
    ]);

    expect(result.exitCode, 1);
    expect(
      result.stderr,
      contains('Frame-time and memory thresholds must remain disabled'),
    );
  });
}
