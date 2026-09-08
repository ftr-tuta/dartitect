import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('accepts the checked-in UI quality evidence', () async {
    final result = await Process.run(Platform.resolvedExecutable, <String>[
      'tool/check_ui_quality.dart',
    ]);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('ui-quality-v2 passed'));
  });

  test('rejects incomplete UI quality evidence', () async {
    final sourceRoot = Directory.current.absolute;
    final root = await Directory.systemTemp.createTemp('ui-quality-v2-');
    addTearDown(() => root.delete(recursive: true));
    final contract = jsonDecode(
      File('${sourceRoot.path}/tool/ui_quality_contract.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    contract['topology'] = <String, Object?>{
      'packages': 24,
      'publicEntrypoints': 35,
    };
    final file = File('${root.path}/tool/ui_quality_contract.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(contract));
    await File('${sourceRoot.path}/tool/package_release_contract.json')
        .copy('${root.path}/tool/package_release_contract.json');

    final result = await Process.run(Platform.resolvedExecutable, <String>[
      '${sourceRoot.path}/tool/check_ui_quality.dart',
      '--root=${root.path}',
    ]);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Expected 25 packages'));
  });

  test('rejects a divergent coordinated Actions execution count', () async {
    final sourceRoot = Directory.current.absolute;
    final root = await Directory.systemTemp.createTemp('ui-quality-actions-');
    addTearDown(() => root.delete(recursive: true));
    final contract = jsonDecode(
      File('${sourceRoot.path}/tool/ui_quality_contract.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    (contract['githubActionsEvidence']!
            as Map<String, Object?>)['coordinatedExecutions'] =
        8;
    final file = File('${root.path}/tool/ui_quality_contract.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(contract));
    await File('${sourceRoot.path}/tool/package_release_contract.json')
        .copy('${root.path}/tool/package_release_contract.json');

    final result = await Process.run(Platform.resolvedExecutable, <String>[
      '${sourceRoot.path}/tool/check_ui_quality.dart',
      '--root=${root.path}',
    ]);

    expect(result.exitCode, isNot(0));
    expect(
      result.stderr,
      contains('Deterministic GitHub Actions evidence is incomplete'),
    );
  });
}
