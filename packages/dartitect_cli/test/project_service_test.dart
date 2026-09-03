import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:dartitect_cli/src/scan/baseline.dart';
import 'package:test/test.dart';

void main() {
  test(
    'CLI inspect is the project service JSON without text parsing',
    () async {
      final root = await _project();
      final output = StringBuffer();
      final errors = StringBuffer();
      final exitCode = await DartitectCliRunner(
        currentDirectory: root,
        stdoutSink: output,
        stderrSink: errors,
      ).run(<String>['inspect', '--json']);
      final service = await DartitectProjectService(root).inspectProject();

      expect(exitCode, service.exitCode);
      expect(jsonDecode(output.toString()), service.toJson());
      expect(errors.toString(), isEmpty);
    },
  );

  test('service rejects a stale baseline plan before commit', () async {
    final root = await _project(
      source: "import 'package:flutter/widgets.dart';\n",
      sourcePath: 'lib/features/example/domain/model.dart',
    );
    final service = DartitectProjectService(root);
    final plan = await service.previewChange(DartitectChangeKind.baseline);
    await File('${root.path}/lib/features/example/domain/model.dart')
        .writeAsString('BuildContext? context;\n');

    await expectLater(
      service.applyChange(plan),
      throwsA(
        isA<DartitectChangeException>().having(
          (error) => error.code,
          'code',
          'stale_plan',
        ),
      ),
    );
    expect(File('${root.path}/.dartitect/baseline.json').existsSync(), isFalse);
  });

  test('baseline plan uses a SHA-256 semantic state token', () async {
    final root = await _project();

    final plan = await DartitectProjectService(root)
        .previewChange(DartitectChangeKind.baseline);

    expect(plan.stateToken, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(plan.semanticManifest.digest, plan.stateToken);
    expect(plan.toJson()['schemaVersion'], 1);
    expect(plan.semanticManifest.toJson()['schemaVersion'], 1);
    expect(
      plan.semanticManifest.inputs.map((input) => input.path),
      orderedEquals(
        plan.semanticManifest.inputs.map((input) => input.path).toList()
          ..sort(),
      ),
    );
  });

  test('irrelevant assets do not invalidate a baseline plan', () async {
    final root = await _project(
      source: "import 'package:flutter/widgets.dart';\n",
      sourcePath: 'lib/features/example/domain/model.dart',
    );
    final service = DartitectProjectService(root);
    final plan = await service.previewChange(DartitectChangeKind.baseline);
    final asset = File('${root.path}/assets/catalog.bin');
    await asset.parent.create(recursive: true);
    await asset.writeAsBytes(List<int>.filled(128 * 1024, 7));

    final receipt = await service.applyChange(plan);

    expect(receipt.changed, isTrue);
    expect(receipt.toJson()['schemaVersion'], 1);
    expect(File('${root.path}/.dartitect/baseline.json').existsSync(), isTrue);
  });

  test(
    'concurrent applications serialize revalidation through commit',
    () async {
      final root = await _project(
        source: "import 'package:flutter/widgets.dart';\n",
        sourcePath: 'lib/features/example/domain/model.dart',
      );
      final firstService = DartitectProjectService(root);
      final secondService = DartitectProjectService(root);
      final plan = await firstService.previewChange(
        DartitectChangeKind.baseline,
      );

      final outcomes = await Future.wait<Object>([
        firstService
            .applyChange(plan)
            .then<Object>((value) => value)
            .catchError((Object error) => error),
        secondService
            .applyChange(plan)
            .then<Object>((value) => value)
            .catchError((Object error) => error),
      ]);

      expect(outcomes.whereType<DartitectChangeReceipt>(), hasLength(1));
      expect(
        outcomes.whereType<DartitectChangeException>().single.code,
        'change_locked',
      );
      expect(
        await DartitectBaseline.load(
          File('${root.path}/.dartitect/baseline.json'),
        ),
        isA<DartitectBaseline>(),
      );
    },
  );

  test('two processes cannot apply the same baseline state', () async {
    final root = await _project(
      source: "import 'package:flutter/widgets.dart';\n",
      sourcePath: 'lib/features/example/domain/model.dart',
    );
    final barrier = await Directory.systemTemp.createTemp(
      'dartitect-change-barrier-',
    );
    addTearDown(() async {
      if (await barrier.exists()) await barrier.delete(recursive: true);
    });
    final workspaceHelper = File(
      '${Directory.current.path}/packages/dartitect_cli/test/fixtures/'
      'project_change_racer.dart',
    );
    final helper = await workspaceHelper.exists()
        ? workspaceHelper
        : File(
            '${Directory.current.path}/test/fixtures/'
            'project_change_racer.dart',
          );
    expect(await helper.exists(), isTrue, reason: helper.path);
    final racers = <Process>[
      await Process.start(Platform.resolvedExecutable, <String>[
        helper.path,
        root.path,
        barrier.path,
        'first',
      ]),
      await Process.start(Platform.resolvedExecutable, <String>[
        helper.path,
        root.path,
        barrier.path,
        'second',
      ]),
    ];
    addTearDown(() {
      for (final racer in racers) {
        racer.kill();
      }
    });
    for (final id in const <String>['first', 'second']) {
      final ready = File('${barrier.path}/$id.ready');
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (!await ready.exists() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(await ready.exists(), isTrue, reason: '$id did not reach barrier');
    }
    await File('${barrier.path}/go').writeAsString('go\n', flush: true);

    final outputs = <Map<String, Object?>>[];
    for (final racer in racers) {
      final stdoutText = await utf8.decoder.bind(racer.stdout).join();
      final stderrText = await utf8.decoder.bind(racer.stderr).join();
      expect(await racer.exitCode, 0, reason: stderrText);
      outputs.add(
        (jsonDecode(stdoutText.trim())! as Map<Object?, Object?>).cast(),
      );
    }

    expect(
      outputs.where((value) => value['outcome'] == 'receipt'),
      hasLength(1),
    );
    final rejected = outputs.singleWhere(
      (value) => value['outcome'] == 'rejected',
    );
    expect(rejected['code'], anyOf('change_locked', 'stale_plan'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'OS releases an interrupted process lock without corrupting commit',
    () async {
      final root = await _project(
        source: "import 'package:flutter/widgets.dart';\n",
        sourcePath: 'lib/features/example/domain/model.dart',
      );
      final service = DartitectProjectService(root);
      final plan = await service.previewChange(DartitectChangeKind.baseline);
      final lockDirectory = Directory('${root.path}/.dartitect');
      await lockDirectory.create();
      final helperRoot =
          await File(
            '${Directory.current.path}/packages/dartitect_cli/test/fixtures/'
            'project_lock_holder.dart',
          ).exists()
          ? '${Directory.current.path}/packages/dartitect_cli/test/fixtures'
          : '${Directory.current.path}/test/fixtures';
      final holder = await Process.start(Platform.resolvedExecutable, <String>[
        '$helperRoot/project_lock_holder.dart',
        '${lockDirectory.path}/project-change.lock',
      ]);
      final locked = await holder.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 20));
      expect(locked, 'locked');

      expect(holder.kill(), isTrue);
      await holder.exitCode.timeout(const Duration(seconds: 20));
      final releaseDeadline = DateTime.now().add(const Duration(seconds: 5));
      late DartitectChangeReceipt receipt;
      while (true) {
        try {
          receipt = await service.applyChange(plan);
          break;
        } on DartitectChangeException catch (error) {
          if (error.code != 'change_locked' ||
              DateTime.now().isAfter(releaseDeadline)) {
            rethrow;
          }
          // Windows may report process exit just before it releases the
          // terminated process's file handles. Wait only for that OS cleanup.
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      }

      expect(receipt.changed, isTrue);
      expect(
        await DartitectBaseline.load(
          File('${root.path}/.dartitect/baseline.json'),
        ),
        isA<DartitectBaseline>(),
      );
    },
  );

  test('conformance audit never emits a migration plan', () async {
    final root = await _project();

    final audit = await DartitectProjectService(root).auditConformance();

    expect(audit['command'], 'conformance audit');
    expect(audit['canonicalGate'], 'dartitect scan');
    expect(audit, isNot(contains('steps')));
    expect(audit['support'], <String, Object?>{
      'target': 'greenfield_only',
      'existingProjects': 'audit_only',
      'migration': false,
    });
  });

  test(
    'baseline commit is idempotent and leaves no transaction artifacts',
    () async {
      final root = await _project();
      final service = DartitectProjectService(root);
      final first = await service.previewChange(DartitectChangeKind.baseline);
      final receipt = await service.applyChange(first);
      expect(receipt.changed, isTrue);
      final second = await service.previewChange(DartitectChangeKind.baseline);
      final noOp = await service.applyChange(second);
      expect(noOp.changed, isFalse);
      for (final path in <String>[
        'baseline.json.stage',
        'baseline.json.backup',
        'baseline.transaction.json',
      ]) {
        expect(File('${root.path}/.dartitect/$path').existsSync(), isFalse);
      }
    },
  );

  test('baseline commit recovers an interrupted backup before replacing', () async {
    final root = await _project(
      source: "import 'package:flutter/widgets.dart';\n",
      sourcePath: 'lib/features/example/domain/model.dart',
    );
    final directory = Directory('${root.path}/.dartitect');
    await directory.create();
    final original = DartitectBaseline(const <String>['old']).encode();
    await File('${directory.path}/baseline.json.backup')
        .writeAsString(original);
    await File('${directory.path}/baseline.json').writeAsString('partial');
    await File('${directory.path}/baseline.json.stage').writeAsString('stage');
    await File('${directory.path}/baseline.transaction.json').writeAsString(
      '${jsonEncode(<String, Object?>{'schemaVersion': 1, 'phase': 'backedUp'})}\n',
    );

    final service = DartitectProjectService(root);
    final plan = await service.previewChange(DartitectChangeKind.baseline);
    await service.applyChange(plan);

    final restored = await DartitectBaseline.load(
      File('${directory.path}/baseline.json'),
    );
    expect(restored.fingerprints, isNot(<String>{'old'}));
    for (final path in <String>[
      'baseline.json.stage',
      'baseline.json.backup',
      'baseline.transaction.json',
    ]) {
      expect(File('${directory.path}/$path').existsSync(), isFalse);
    }
  });

  test(
    'Codex sync recovery restores the pre-transaction managed skill',
    () async {
      final root = await _project();
      final synchronizer = CodexSkillSynchronizer(root);
      await synchronizer.sync();
      final skills = Directory('${root.path}/.agents/skills');
      final target = Directory('${skills.path}/dartitect-runtime');
      final oldSkill = File('${target.path}/SKILL.md');
      final oldContent = await oldSkill.readAsString();
      final backup = Directory('${root.path}/.dartitect-codex-backup');
      await backup.create();
      await target.rename('${backup.path}/dartitect-runtime');
      await target.create();
      await File('${target.path}/SKILL.md').writeAsString('partial\n');
      await File('${root.path}/.dartitect-codex-sync.json').writeAsString(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'phase': 'staged',
          'skills': <String>['dartitect-runtime'],
        }),
      );

      await synchronizer.recover();

      expect(await File('${target.path}/SKILL.md').readAsString(), oldContent);
      expect(await backup.exists(), isFalse);
      expect(
        await File('${root.path}/.dartitect-codex-sync.json').exists(),
        isFalse,
      );
    },
  );

  test(
    'dependency upgrade migrates RC10 and only Dartitect overrides',
    () async {
      final root = await _project();
      final pubspec = File('${root.path}/pubspec.yaml');
      await pubspec.writeAsString('''name: fixture
dependencies:
  # direct dependencies stay ordered
  dartitect: ^1.0.0-rc.10 # core
  http: ^1.0.0
dev_dependencies:
  dartitect_testing: ">=1.0.0-rc.10 <1.0.0"
dependency_overrides:
  dartitect:
    path: ../dartitect
  meta: ^1.0.0 # external override
''');
      final commands = <String>[];
      final service = DartitectProjectService(root);

      final plan = await service.previewDependencyUpgrade('1.1.0');
      final receipt = await _withUpgradeCommandRunner((
        project,
        executable,
        arguments,
      ) async {
        commands.add('$executable ${arguments.join(' ')}');
        return ProcessResult(1, 0, '', '');
      }, () => service.applyChange(plan));
      final result = await pubspec.readAsString();

      expect(plan.targetCohort, '1.1.0');
      expect(receipt.changed, isTrue);
      expect(result, contains('# direct dependencies stay ordered'));
      expect(result, contains('dartitect: # core'));
      expect(result, contains('path: packages/dartitect'));
      expect(result, contains('path: packages/dartitect_testing'));
      expect(result, contains("tag_pattern: 'v{{version}}'"));
      expect(result, contains('version: 1.1.0'));
      expect(result, contains('  http: ^1.0.0'));
      expect(result, contains('  meta: ^1.0.0 # external override'));
      expect(result, isNot(contains('path: ../dartitect')));
      expect(commands, <String>['dart pub get', 'dart analyze', 'dart test']);
      for (final path in <String>[
        'dependency-upgrade.pubspec.stage',
        'dependency-upgrade.pubspec.backup',
        'dependency-upgrade.pubspec.lock.backup',
        'dependency-upgrade.transaction.json',
      ]) {
        expect(File('${root.path}/.dartitect/$path').existsSync(), isFalse);
      }
    },
  );

  test('dependency upgrade canonicalizes an old Git descriptor', () async {
    const source = '''name: fixture
dependencies:
  dartitect_flutter:
    git:
      url: https://github.com/ftr-tuta/dartitect.git
      path: packages/dartitect_flutter
      ref: v1.0.0-rc.10
    version: 1.0.0-rc.10
''';

    final result = DartitectProjectService.renderDependencyUpgradeSource(
      source,
      '1.1.0',
    );

    expect(result, contains('path: packages/dartitect_flutter'));
    expect(result, contains("tag_pattern: 'v{{version}}'"));
    expect(result, contains('version: 1.1.0'));
    expect(result, isNot(contains('ref:')));
  });

  test('dependency upgrade preserves comments and CRLF idempotently', () async {
    const source =
        'name: fixture\r\ndependencies:\r\n'
        '  dartitect: 1.0.0-rc.10 # direct\r\n'
        '  collection: ^1.0.0\r\n';

    final first = DartitectProjectService.renderDependencyUpgradeSource(
      source,
      '1.1.0',
    );
    final second = DartitectProjectService.renderDependencyUpgradeSource(
      first,
      '1.1.0',
    );

    expect(first, second);
    expect(first, contains('dartitect: # direct\r\n'));
    expect(first, contains('  collection: ^1.0.0\r\n'));
    expect(first.replaceAll('\r\n', ''), isNot(contains('\n')));
  });

  test('dependency upgrade rejects stale and unsupported plans', () async {
    final root = await _project();
    final pubspec = File('${root.path}/pubspec.yaml');
    await pubspec.writeAsString('''name: fixture
dependencies:
  dartitect: 1.0.0-rc.10
''');
    final service = DartitectProjectService(root);
    final plan = await service.previewDependencyUpgrade('1.1.0');
    await pubspec.writeAsString('''name: fixture
dependencies:
  dartitect: ^1.0.0-rc.10
''');

    await expectLater(
      service.applyChange(plan),
      throwsA(
        isA<DartitectChangeException>().having(
          (error) => error.code,
          'code',
          'stale_plan',
        ),
      ),
    );
    await pubspec.writeAsString('''name: fixture
dependencies:
  dartitect:
    path: ../sdk
''');
    await expectLater(
      service.previewDependencyUpgrade('1.1.0'),
      throwsA(
        isA<DartitectChangeException>().having(
          (error) => error.code,
          'code',
          'unsupported_dependency_source',
        ),
      ),
    );
  });

  test(
    'dependency upgrade rolls pubspec and lock back on validation failure',
    () async {
      final root = await _project();
      final pubspec = File('${root.path}/pubspec.yaml');
      final lockfile = File('${root.path}/pubspec.lock');
      const original = '''name: fixture
dependencies:
  dartitect: 1.0.0-rc.10
''';
      await pubspec.writeAsString(original);
      await lockfile.writeAsString('original lock\n');
      final service = DartitectProjectService(root);
      final plan = await service.previewDependencyUpgrade('1.1.0');

      await expectLater(
        _withUpgradeCommandRunner((project, executable, arguments) async {
          if (arguments.first == 'pub') {
            await File('${project.path}/pubspec.lock')
                .writeAsString('new lock\n');
            return ProcessResult(1, 0, '', '');
          }
          return ProcessResult(1, 1, '', 'analysis failed');
        }, () => service.applyChange(plan)),
        throwsA(
          isA<DartitectChangeException>().having(
            (error) => error.code,
            'code',
            'dependency_upgrade_validation_failed',
          ),
        ),
      );

      expect(await pubspec.readAsString(), original);
      expect(await lockfile.readAsString(), 'original lock\n');
      expect(
        File('${root.path}/.dartitect/dependency-upgrade.transaction.json')
            .existsSync(),
        isFalse,
      );
    },
  );

  test('dependency upgrade recovers a journal before applying', () async {
    final root = await _project();
    final pubspec = File('${root.path}/pubspec.yaml');
    final lockfile = File('${root.path}/pubspec.lock');
    const original = '''name: fixture
dependencies:
  dartitect: 1.0.0-rc.10
''';
    await pubspec.writeAsString(original);
    await lockfile.writeAsString('original lock\n');
    final service = DartitectProjectService(root);
    final plan = await service.previewDependencyUpgrade('1.1.0');
    final transaction = Directory('${root.path}/.dartitect');
    await transaction.create();
    await File('${transaction.path}/dependency-upgrade.pubspec.backup')
        .writeAsString(original);
    await File('${transaction.path}/dependency-upgrade.pubspec.lock.backup')
        .writeAsString('original lock\n');
    await File('${transaction.path}/dependency-upgrade.pubspec.stage')
        .writeAsString('partial');
    await pubspec.writeAsString('name: partial\n');
    await lockfile.writeAsString('partial lock\n');
    await File(
      '${transaction.path}/dependency-upgrade.transaction.json',
    ).writeAsString(
      '${jsonEncode(<String, Object?>{'schemaVersion': 1, 'phase': 'validating', 'targetSha256': '0' * 64, 'lockfileExisted': true})}\n',
    );
    final receipt = await _withUpgradeCommandRunner(
      _successfulUpgradeCommand,
      () => service.applyChange(plan),
    );

    expect(receipt.changed, isTrue);
    expect(await pubspec.readAsString(), contains('version: 1.1.0'));
    expect(
      File('${transaction.path}/dependency-upgrade.transaction.json')
          .existsSync(),
      isFalse,
    );
  });
}

typedef _UpgradeCommandRunner = Future<ProcessResult> Function(
  Directory root,
  String executable,
  List<String> arguments,
);

Future<T> _withUpgradeCommandRunner<T>(
  _UpgradeCommandRunner runner,
  Future<T> Function() action,
) => runZoned<Future<T>>(
  action,
  zoneValues: <Object?, Object?>{#dartitectUpgradeCommandRunner: runner},
);

Future<ProcessResult> _successfulUpgradeCommand(
  Directory root,
  String executable,
  List<String> arguments,
) async => ProcessResult(1, 0, '', '');

Future<Directory> _project({
  String source = 'void main() {}\n',
  String sourcePath = 'lib/main.dart',
}) async {
  final root = await Directory.systemTemp.createTemp('dartitect-service-test-');
  addTearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });
  await File('${root.path}/pubspec.yaml').writeAsString('''name: fixture
environment:
  sdk: ^3.13.0
''');
  final file = File('${root.path}/$sourcePath');
  await file.parent.create(recursive: true);
  await file.writeAsString(source);
  return root;
}
