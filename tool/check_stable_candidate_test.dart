import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'stable policy requires native cells and deterministic Actions evidence',
    () async {
      final sourceRoot = Directory.current.absolute;
      final checker = '${sourceRoot.path}/tool/check_stable_candidate.dart';
      final accepted = await Process.run(Platform.resolvedExecutable, <String>[
        checker,
        '--root=${sourceRoot.path}',
        '--contract-only',
      ]);
      final root = await Directory.systemTemp.createTemp('stable-policy-v2-');
      addTearDown(() => root.delete(recursive: true));
      await Directory('${root.path}/tool').create(recursive: true);
      final destination = File(
        '${root.path}/tool/stable_candidate_contract.json',
      );
      await File(
        '${Directory.current.path}/tool/stable_candidate_contract.json',
      ).copy(destination.path);
      final contract =
          jsonDecode(destination.readAsStringSync()) as Map<String, Object?>;
      (contract['requiredNativeCells']! as List<Object?>).add('extra-cell');
      await destination.writeAsString(jsonEncode(contract));
      final rejected = await Process.run(Platform.resolvedExecutable, <String>[
        checker,
        '--root=${root.path}',
        '--contract-only',
      ]);

      expect(accepted.exitCode, 0);
      expect(accepted.stdout, contains('ui-quality-v2'));
      expect(
        File('${Directory.current.path}/tool/stable_candidate_contract.json')
            .readAsStringSync(),
        contains('requiresDeterministicActionsEvidence'),
      );
      expect(rejected.exitCode, 1);
    },
  );
}
