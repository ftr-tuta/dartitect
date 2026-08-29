import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test(
    'canary archives an exact commit and mutates only a temporary copy',
    () async {
      final candidate = await Directory.systemTemp.createTemp(
        'dartitect-candidate-',
      );
      final fleet = await Directory.systemTemp.createTemp('dartitect-fleet-');
      addTearDown(() async {
        if (await candidate.exists()) await candidate.delete(recursive: true);
        if (await fleet.exists()) await fleet.delete(recursive: true);
      });
      final package = Directory('${candidate.path}/packages/dartitect/lib');
      await package.create(recursive: true);
      await File('${candidate.path}/packages/dartitect/pubspec.yaml')
          .writeAsString('''
name: dartitect
version: 1.0.0-rc.6
environment:
  sdk: ^3.13.0
''');
      await File('${package.path}/dartitect.dart').writeAsString('''
library;
const candidateValue = 5;
''');
      await _git(candidate, <String>['init']);
      await _git(candidate, <String>['config', 'user.name', 'Canary Test']);
      await _git(candidate, <String>[
        'config',
        'user.email',
        'canary@example.invalid',
      ]);
      await _git(candidate, <String>['add', '.']);
      await _git(candidate, <String>['commit', '-m', 'candidate']);
      final commit = (await _git(candidate, <String>[
        'rev-parse',
        'HEAD',
      ])).trim();
      await File('${candidate.path}/untracked-marker')
          .writeAsString('preserve');

      final app = Directory('${fleet.path}/app/lib');
      await app.create(recursive: true);
      await File('${fleet.path}/app/pubspec.yaml').writeAsString('''
name: canary_consumer
environment:
  sdk: ^3.13.0
dependencies:
  dartitect: any
''');
      await File('${app.path}/main.dart').writeAsString('''
import 'package:dartitect/dartitect.dart';
void main() => print(candidateValue);
''');
      final originalPubspec = await File('${fleet.path}/app/pubspec.yaml')
          .readAsString();

      final receipt =
          await DartitectFleetCanaryService(
            candidateRepository: candidate,
            fleetRoot: fleet,
          ).run(
            projectRoot: 'app',
            candidateCommit: commit,
            commands: const <DartitectFleetCanaryCommand>[
              DartitectFleetCanaryCommand.dartPubGet,
              DartitectFleetCanaryCommand.dartAnalyze,
            ],
          );

      expect(receipt.exitCode, 0);
      expect(receipt.candidateCommit, commit);
      expect(receipt.candidateRepositoryUnchanged, isTrue);
      expect(receipt.projectUnchanged, isTrue);
      expect(receipt.temporaryCopyRemoved, isTrue);
      expect(receipt.commands, hasLength(2));
      final encoded = jsonEncode(receipt.toJson());
      expect(encoded, isNot(contains(candidate.path)));
      expect(encoded, isNot(contains(fleet.path)));
      expect(
        await File('${fleet.path}/app/pubspec.yaml').readAsString(),
        originalPubspec,
      );
      expect(
        File('${fleet.path}/app/pubspec_overrides.yaml').existsSync(),
        false,
      );
      expect(
        await File('${candidate.path}/untracked-marker').readAsString(),
        'preserve',
      );
    },
  );

  test('canary requires an exact full commit SHA before copying', () async {
    final candidate = await Directory.systemTemp.createTemp(
      'dartitect-candidate-',
    );
    final fleet = await Directory.systemTemp.createTemp('dartitect-fleet-');
    addTearDown(() async {
      if (await candidate.exists()) await candidate.delete(recursive: true);
      if (await fleet.exists()) await fleet.delete(recursive: true);
    });
    await expectLater(
      DartitectFleetCanaryService(
        candidateRepository: candidate,
        fleetRoot: fleet,
      ).run(
        projectRoot: 'app',
        candidateCommit: 'HEAD',
        commands: const <DartitectFleetCanaryCommand>[
          DartitectFleetCanaryCommand.dartAnalyze,
        ],
      ),
      throwsFormatException,
    );
  });
}

Future<String> _git(Directory root, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: root.path,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.first} failed: ${result.stderr}');
  }
  return '${result.stdout}';
}
