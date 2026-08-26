import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test(
    'dry-run writes nothing and committed re-execution is a no-op',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'dartitect generation ',
      );
      addTearDown(() => root.delete(recursive: true));
      final engine = GenerationEngine(root);
      const operations = <FileGenerationOperation>[
        FileGenerationOperation(relativePath: 'lib/a.dart', content: 'a\n'),
        FileGenerationOperation(relativePath: 'lib/b.dart', content: 'b\n'),
      ];

      final dryRun = await engine.apply(operations, dryRun: true);
      expect(dryRun.plan.creates, hasLength(2));
      expect(await File('${root.path}/lib/a.dart').exists(), isFalse);

      final committed = await engine.apply(operations);
      expect(committed.createdPaths, <String>['lib/a.dart', 'lib/b.dart']);
      final repeated = await engine.apply(operations);
      expect(
        repeated.plan.operations.map((operation) => operation.disposition),
        everyElement(GenerationDisposition.noOp),
      );
    },
  );

  test('conflict aborts before creating any other file', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-conflict-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/existing.txt').writeAsString('consumer\n');

    await expectLater(
      GenerationEngine(root).apply(const <FileGenerationOperation>[
        FileGenerationOperation(
          relativePath: 'existing.txt',
          content: 'generated\n',
        ),
        FileGenerationOperation(relativePath: 'new.txt', content: 'new\n'),
      ]),
      throwsA(isA<GenerationException>()),
    );

    expect(
      await File('${root.path}/existing.txt').readAsString(),
      'consumer\n',
    );
    expect(await File('${root.path}/new.txt').exists(), isFalse);
  });

  test('rejects path traversal and duplicate divergent operations', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-safe-path-');
    addTearDown(() => root.delete(recursive: true));
    final engine = GenerationEngine(root);

    await expectLater(
      engine.plan(const <FileGenerationOperation>[
        FileGenerationOperation(relativePath: '../escape', content: ''),
      ]),
      throwsA(isA<GenerationException>()),
    );
    await expectLater(
      engine.plan(const <FileGenerationOperation>[
        FileGenerationOperation(relativePath: 'same', content: 'a'),
        FileGenerationOperation(relativePath: 'same', content: 'b'),
      ]),
      throwsA(isA<GenerationException>()),
    );
  });

  test('rejects existing directories and symlink traversal', () async {
    final root = await Directory.systemTemp.createTemp(
      'dartitect-symlink-root-',
    );
    final outside = await Directory.systemTemp.createTemp(
      'dartitect-symlink-outside-',
    );
    addTearDown(() => root.delete(recursive: true));
    addTearDown(() => outside.delete(recursive: true));
    await Directory('${root.path}/directory_target').create();
    final engine = GenerationEngine(root);

    final directoryPlan = await engine.plan(const <FileGenerationOperation>[
      FileGenerationOperation(relativePath: 'directory_target', content: ''),
    ]);
    expect(
      directoryPlan.operations.single.disposition,
      GenerationDisposition.conflict,
    );

    if (!Platform.isWindows) {
      await Link('${root.path}/linked').create(outside.path);
      await expectLater(
        engine.plan(const <FileGenerationOperation>[
          FileGenerationOperation(
            relativePath: 'linked/escape.txt',
            content: 'escape',
          ),
        ]),
        throwsA(isA<GenerationException>()),
      );
      expect(await File('${outside.path}/escape.txt').exists(), isFalse);
    }
  });

  test('treats CRLF as an idempotent generated result', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-crlf-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/same.txt').writeAsString('same\r\n');

    final plan = await GenerationEngine(root)
        .plan(const <FileGenerationOperation>[
          FileGenerationOperation(relativePath: 'same.txt', content: 'same\n'),
        ]);

    expect(plan.operations.single.disposition, GenerationDisposition.noOp);
    expect(await File('${root.path}/same.txt').readAsString(), 'same\r\n');
  });

  test(
    'fully-generated files converge through create update and delete',
    () async {
      final root = await Directory.systemTemp.createTemp('dartitect-owned-');
      addTearDown(() => root.delete(recursive: true));
      final engine = GenerationEngine(root);
      FileGenerationOperation model(String content) => FileGenerationOperation(
        relativePath: 'lib/user.dartitect.g.dart',
        content: content,
        ownership: GeneratedOwnership.fullyGenerated,
        sourcePath: 'lib/user.dart',
        inputSignature: content,
      );

      final created = await engine.apply(<FileGenerationOperation>[
        model('v1\n'),
      ], manageFullyGenerated: true);
      expect(created.createdPaths, <String>['lib/user.dartitect.g.dart']);
      expect(
        await File('${root.path}/.dartitect/model-outputs.json').exists(),
        isTrue,
      );

      final updated = await engine.apply(<FileGenerationOperation>[
        model('v2\r\n'),
      ], manageFullyGenerated: true);
      expect(updated.updatedPaths, <String>['lib/user.dartitect.g.dart']);
      expect(
        await File('${root.path}/lib/user.dartitect.g.dart').readAsString(),
        'v2\n',
      );

      final deleted = await engine.apply(
        const <FileGenerationOperation>[],
        manageFullyGenerated: true,
      );
      expect(deleted.deletedPaths, <String>['lib/user.dartitect.g.dart']);
      expect(
        await File('${root.path}/lib/user.dartitect.g.dart').exists(),
        isFalse,
      );
    },
  );

  test('consumer edit blocks an entire fully-generated transaction', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-owned-edit-');
    addTearDown(() => root.delete(recursive: true));
    final engine = GenerationEngine(root);
    const original = FileGenerationOperation(
      relativePath: 'lib/a.dartitect.g.dart',
      content: 'owned\n',
      ownership: GeneratedOwnership.fullyGenerated,
      sourcePath: 'lib/a.dart',
      inputSignature: 'a',
    );
    await engine.apply(const <FileGenerationOperation>[
      original,
    ], manageFullyGenerated: true);
    await File('${root.path}/lib/a.dartitect.g.dart')
        .writeAsString('consumer\n');

    await expectLater(
      engine.apply(
        const <FileGenerationOperation>[],
        manageFullyGenerated: true,
      ),
      throwsA(isA<GenerationException>()),
    );
    expect(
      await File('${root.path}/lib/a.dartitect.g.dart').readAsString(),
      'consumer\n',
    );
  });

  test(
    'missing and corrupt manifests fail closed around candidate outputs',
    () async {
      final root = await Directory.systemTemp.createTemp('dartitect-manifest-');
      addTearDown(() => root.delete(recursive: true));
      await Directory('${root.path}/lib').create(recursive: true);
      await File('${root.path}/lib/a.dartitect.g.dart')
          .writeAsString('candidate\n');
      final plan = await GenerationEngine(root)
          .plan(const <FileGenerationOperation>[], manageFullyGenerated: true);
      expect(plan.hasConflicts, isTrue);

      await Directory('${root.path}/.dartitect').create();
      await File('${root.path}/.dartitect/model-outputs.json')
          .writeAsString('{bad');
      await expectLater(
        GenerationEngine(
          root,
        ).plan(const <FileGenerationOperation>[], manageFullyGenerated: true),
        throwsA(
          isA<GenerationException>().having(
            (error) => error.kind,
            'kind',
            GenerationFailureKind.invalidConfiguration,
          ),
        ),
      );
    },
  );

  test('unsupported manifest schema fails closed without writes', () async {
    for (final schema in <int>[0, 2]) {
      final root = await Directory.systemTemp.createTemp(
        'dartitect-manifest-schema-$schema-',
      );
      addTearDown(() => root.delete(recursive: true));
      await Directory('${root.path}/.dartitect').create(recursive: true);
      final manifest = File('${root.path}/.dartitect/model-outputs.json');
      final original = jsonEncode(<String, Object?>{
        'schemaVersion': schema,
        'outputs': const <Object?>[],
      });
      await manifest.writeAsString(original);

      await expectLater(
        GenerationEngine(root).apply(const <FileGenerationOperation>[
          FileGenerationOperation(relativePath: 'lib/new.dart', content: ''),
        ], manageFullyGenerated: true),
        throwsA(
          isA<GenerationException>().having(
            (error) => error.kind,
            'kind',
            GenerationFailureKind.invalidConfiguration,
          ),
        ),
        reason: 'schema $schema',
      );
      expect(await manifest.readAsString(), original, reason: 'schema $schema');
      expect(
        await File('${root.path}/lib/new.dart').exists(),
        isFalse,
        reason: 'schema $schema',
      );
    }
  });

  test('unsupported journal schema preserves recovery residue', () async {
    for (final schema in <int>[1, 3]) {
      final root = await Directory.systemTemp.createTemp(
        'dartitect-journal-schema-$schema-',
      );
      addTearDown(() => root.delete(recursive: true));
      await Directory('${root.path}/.dartitect').create(recursive: true);
      final journal = File('${root.path}/.dartitect/generation-journal.json');
      final original = '{"schemaVersion":$schema,"phase":"committing"}\n';
      await journal.writeAsString(original);
      final consumer = File('${root.path}/lib/consumer.dart');
      await consumer.create(recursive: true);
      await consumer.writeAsString('consumer\n');

      await expectLater(
        GenerationEngine(root).recover(),
        throwsA(
          isA<GenerationException>()
              .having(
                (error) => error.kind,
                'kind',
                GenerationFailureKind.recovery,
              )
              .having(
                (error) => error.recoveryPaths,
                'recovery paths',
                <String>['.dartitect/generation-journal.json'],
              ),
        ),
        reason: 'schema $schema',
      );
      expect(await journal.readAsString(), original, reason: 'schema $schema');
      expect(
        await consumer.readAsString(),
        'consumer\n',
        reason: 'schema $schema',
      );
    }
  });

  test('journal v2 restores update/delete bytes and removes creates', () async {
    final root = await Directory.systemTemp.createTemp(
      'dartitect-recovery-v2-',
    );
    addTearDown(() => root.delete(recursive: true));
    const oldUpdate = 'old update\r\n';
    const newUpdate = 'new update\n';
    const oldDelete = 'old delete\r\n';
    const created = 'created\n';
    await Directory('${root.path}/lib').create(recursive: true);
    await File('${root.path}/lib/update.dart').writeAsString(newUpdate);
    await File('${root.path}/lib/create.dart').writeAsString(created);
    final transaction = Directory(
      '${root.path}/.dartitect/generation-transaction',
    );
    await File('${transaction.path}/backup/lib/update.dart')
        .create(recursive: true)
        .then((file) => file.writeAsString(oldUpdate));
    await File('${transaction.path}/backup/lib/delete.dart')
        .create(recursive: true)
        .then((file) => file.writeAsString(oldDelete));
    await File('${root.path}/.dartitect/generation-journal.json').writeAsString(
      jsonEncode(<String, Object?>{
        'schemaVersion': 2,
        'phase': 'committing',
        'entries': <Object?>[
          _journalEntry('lib/update.dart', 'update', oldUpdate, newUpdate),
          _journalEntry('lib/delete.dart', 'delete', oldDelete, null),
          _journalEntry('lib/create.dart', 'create', null, created),
        ],
        'manifest': null,
      }),
    );

    await GenerationEngine(root).recover();

    expect(
      await File('${root.path}/lib/update.dart').readAsString(),
      oldUpdate,
    );
    expect(
      await File('${root.path}/lib/delete.dart').readAsString(),
      oldDelete,
    );
    expect(await File('${root.path}/lib/create.dart').exists(), isFalse);
    expect(await transaction.exists(), isFalse);
  });

  test(
    'journal v2 preserves concurrent bytes and reports their path',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'dartitect-recovery-conflict-',
      );
      addTearDown(() => root.delete(recursive: true));
      await Directory('${root.path}/lib').create(recursive: true);
      await File('${root.path}/lib/create.dart').writeAsString('consumer\n');
      await Directory('${root.path}/.dartitect').create();
      await File('${root.path}/.dartitect/generation-journal.json')
          .writeAsString(
            jsonEncode(<String, Object?>{
              'schemaVersion': 2,
              'phase': 'committing',
              'entries': <Object?>[
                _journalEntry('lib/create.dart', 'create', null, 'generated\n'),
              ],
              'manifest': null,
            }),
          );

      await expectLater(
        GenerationEngine(root).recover(),
        throwsA(
          isA<GenerationException>().having(
            (error) => error.recoveryPaths,
            'recovery paths',
            <String>['lib/create.dart'],
          ),
        ),
      );
      expect(
        await File('${root.path}/lib/create.dart').readAsString(),
        'consumer\n',
      );
    },
  );

  test('fault matrix recovers or preserves one complete generation', () async {
    for (final point in GenerationFaultPoint.values) {
      final root = await Directory.systemTemp.createTemp(
        'dartitect-fault-${point.name}-',
      );
      addTearDown(() => root.delete(recursive: true));
      FileGenerationOperation model(String content) => FileGenerationOperation(
        relativePath: 'lib/user.dartitect.g.dart',
        content: content,
        ownership: GeneratedOwnership.fullyGenerated,
        sourcePath: 'lib/user.dart',
        inputSignature: content,
      );
      await GenerationEngine(root).apply(<FileGenerationOperation>[
        model('v1\n'),
      ], manageFullyGenerated: true);
      var injected = false;
      final engine = GenerationEngine(
        root,
        faultInjector: (event) {
          if (!injected && event.point == point) {
            injected = true;
            throw StateError('injected ${point.name}');
          }
        },
      );

      await expectLater(
        engine.apply(<FileGenerationOperation>[
          model('v2\n'),
        ], manageFullyGenerated: true),
        throwsA(isA<GenerationException>()),
        reason: point.name,
      );
      expect(injected, isTrue, reason: point.name);

      final retry = GenerationEngine(root);
      await retry.recover();
      await retry.apply(<FileGenerationOperation>[
        model('v2\n'),
      ], manageFullyGenerated: true);
      expect(
        await File('${root.path}/lib/user.dartitect.g.dart').readAsString(),
        'v2\n',
        reason: point.name,
      );
      final manifest = jsonDecode(
        await File('${root.path}/.dartitect/model-outputs.json').readAsString(),
      ) as Map<String, Object?>;
      expect(manifest['outputs'], hasLength(1), reason: point.name);
      expect(
        await File('${root.path}/.dartitect/generation-journal.json').exists(),
        isFalse,
        reason: point.name,
      );
      expect(
        await Directory('${root.path}/.dartitect/generation-transaction')
            .exists(),
        isFalse,
        reason: point.name,
      );
    }
  });
}

Map<String, Object?> _journalEntry(
  String path,
  String disposition,
  String? before,
  String? after,
) => <String, Object?>{
  'path': path,
  'disposition': disposition,
  'beforeExists': before != null,
  'beforeDigest': before == null
      ? null
      : sha256.convert(utf8.encode(before)).toString(),
  'afterExists': after != null,
  'afterDigest': after == null
      ? null
      : sha256.convert(utf8.encode(after)).toString(),
};
