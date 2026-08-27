import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    stderr.writeln('Expected project root, barrier directory, and racer ID.');
    exitCode = 64;
    return;
  }
  final root = Directory(arguments[0]);
  final barrier = Directory(arguments[1]);
  final id = arguments[2];
  final service = DartitectProjectService(root);
  final plan = await service.previewChange(DartitectChangeKind.baseline);
  await File('${barrier.path}/$id.ready').writeAsString('ready\n', flush: true);
  final go = File('${barrier.path}/go');
  while (!await go.exists()) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  try {
    final receipt = await service.applyChange(plan);
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'outcome': 'receipt',
        'changed': receipt.changed,
      }),
    );
  } on DartitectChangeException catch (error) {
    stdout.writeln(
      jsonEncode(<String, Object?>{'outcome': 'rejected', 'code': error.code}),
    );
  }
}
