import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test(
    'checks and applies a confined digest-locked static blueprint',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'dartitect-blueprint-',
      );
      addTearDown(() => root.delete(recursive: true));
      final template = File(
        '${root.path}/blueprints/strict/templates/contract.txt',
      );
      await template.parent.create(recursive: true);
      const content = 'Architecture contract fixture\n';
      await template.writeAsString(content);
      final digest = sha256.convert(utf8.encode(content)).toString();
      final manifest = File('${root.path}/blueprints/strict/blueprint.json');
      await manifest.writeAsString(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'id': 'strict-tests',
          'version': 3,
          'templates': <Object?>[
            <String, Object?>{
              'source': 'templates/contract.txt',
              'path': 'docs/architecture/contract.txt',
              'sha256': digest,
            },
          ],
        }),
      );

      final report = await DartitectBlueprintService(root)
          .inspect('blueprints/strict');
      expect(report.id, 'strict-tests');
      expect(
        report.operations.map((operation) => operation.rendererId),
        containsAll(<String>[
          'blueprint.strict-tests.template',
          'blueprint.strict-tests.digest-lock',
        ]),
      );

      await GenerationEngine(
        root,
        namespace: const GenerationNamespace('blueprint-strict-tests'),
      ).apply(report.operations);
      expect(
        await File('${root.path}/docs/architecture/contract.txt')
            .readAsString(),
        content,
      );
      final lock = jsonDecode(
        await File('${root.path}/.dartitect/blueprints/strict-tests.lock.json')
            .readAsString(),
      ) as Map<String, Object?>;
      expect(lock['manifestSha256'], report.manifestSha256);
    },
  );

  test('rejects executable manifest keys and escaping output paths', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-blueprint-');
    addTearDown(() => root.delete(recursive: true));
    final directory = Directory('${root.path}/blueprint');
    await directory.create();
    await File('${directory.path}/blueprint.json').writeAsString(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'id': 'unsafe',
        'version': 1,
        'templates': const <Object?>[],
        'hooks': <Object?>['dart run arbitrary.dart'],
      }),
    );
    await expectLater(
      DartitectBlueprintService(root).inspect('blueprint'),
      throwsFormatException,
    );

    await File('${directory.path}/template.txt').writeAsString('safe');
    await File('${directory.path}/blueprint.json').writeAsString(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'id': 'unsafe',
        'version': 1,
        'templates': <Object?>[
          <String, Object?>{
            'source': 'template.txt',
            'path': '../outside.txt',
            'sha256': sha256.convert(utf8.encode('safe')).toString(),
          },
        ],
      }),
    );
    await expectLater(
      DartitectBlueprintService(root).inspect('blueprint'),
      throwsFormatException,
    );
  });
}
