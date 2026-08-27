import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('requires the nominal five-cell Actions matrix', () async {
    final root = await Directory.systemTemp.createTemp('rc-validation-v2-');
    addTearDown(() => root.delete(recursive: true));
    await Directory('${root.path}/tool').create(recursive: true);
    final source = File(
      '${Directory.current.path}/tool/rc_validation_contract.json',
    );
    final destination = File('${root.path}/tool/rc_validation_contract.json');
    await source.copy(destination.path);
    final checker = '${Directory.current.path}/tool/check_rc_validation.dart';

    final accepted = await Process.run(Platform.resolvedExecutable, <String>[
      checker,
      '--root=${root.path}',
      '--contract-only',
    ]);
    final contract =
        jsonDecode(destination.readAsStringSync()) as Map<String, Object?>;
    (contract['requiredNativeCells']! as List<Object?>).removeLast();
    await destination.writeAsString(jsonEncode(contract));
    final rejected = await Process.run(Platform.resolvedExecutable, <String>[
      checker,
      '--root=${root.path}',
      '--contract-only',
    ]);

    expect(accepted.exitCode, 0);
    expect(accepted.stdout, contains('nominal five'));
    expect(rejected.exitCode, 1);
  });
}
