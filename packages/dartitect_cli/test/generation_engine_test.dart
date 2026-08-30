import 'dart:async';
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
      final engine = _modelEngine(root);
      const operations = <FileGenerationOperation>[
        FileGenerationOperation(
          relativePath: 'lib/a.dart',
          content: 'a\n',
          rendererId: 'test.fixture',
        ),
        FileGenerationOperation(
          relativePath: 'lib/b.dart',
          content: 'b\n',
          rendererId: 'test.fixture',
        ),
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
      _modelEngine(root).apply(const <FileGenerationOperation>[
        FileGenerationOperation(
          relativePath: 'existing.txt',
          content: 'generated\n',
          rendererId: 'test.fixture',
        ),
        FileGenerationOperation(
          relativePath: 'new.txt',
          content: 'new\n',
          rendererId: 'test.fixture',
        ),
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
    final engine = _modelEngine(root);

    await expectLater(
      engine.plan(const <FileGenerationOperation>[
        FileGenerationOperation(
          relativePath: '../escape',
          content: '',
          rendererId: 'test.fixture',
        ),
      ]),
      throwsA(isA<GenerationException>()),
    );
    await expectLater(
      engine.plan(const <FileGenerationOperation>[
        FileGenerationOperation(
          relativePath: 'same',
          content: 'a',
          rendererId: 'test.fixture',
        ),
        FileGenerationOperation(
          relativePath: 'same',
          content: 'b',
          rendererId: 'test.fixture',
        ),
      ]),
      throwsA(isA<GenerationException>()),
    );
    expect(
      () => GenerationEngine(
        root,
        namespace: const GenerationNamespace(
          'modeling',
          fullyGeneratedSuffix: '.other.g.dart',
        ),
      ),
      throwsA(isA<GenerationException>()),
    );
    expect(
      () => GenerationEngine(
        root,
        namespace: const GenerationNamespace(
          'unsafe',
          fullyGeneratedSuffix: '../owned.dart',
        ),
      ),
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
    final engine = _modelEngine(root);

    final directoryPlan = await engine.plan(const <FileGenerationOperation>[
      FileGenerationOperation(
        relativePath: 'directory_target',
        content: '',
        rendererId: 'test.fixture',
      ),
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
            rendererId: 'test.fixture',
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

    final plan = await _modelEngine(root).plan(const <FileGenerationOperation>[
      FileGenerationOperation(
        relativePath: 'same.txt',
        content: 'same\n',
        rendererId: 'test.fixture',
      ),
    ]);

    expect(plan.operations.single.disposition, GenerationDisposition.noOp);
    expect(await File('${root.path}/same.txt').readAsString(), 'same\r\n');
  });

  test(
    'fully-generated files converge through create update and delete',
    () async {
      final root = await Directory.systemTemp.createTemp('dartitect-owned-');
      addTearDown(() => root.delete(recursive: true));
      final engine = _modelEngine(root);
      FileGenerationOperation model(String content) => FileGenerationOperation(
        relativePath: 'lib/user.dartitect.g.dart',
        content: content,
        rendererId: 'test.fixture',
        ownership: GeneratedOwnership.fullyGenerated,
        sourcePath: 'lib/user.dart',
        inputSignature: content,
      );

      final created = await engine.apply(<FileGenerationOperation>[
        model('v1\n'),
      ], manageFullyGenerated: true);
      expect(created.createdPaths, <String>['lib/user.dartitect.g.dart']);
      expect(
        await File('${root.path}/.dartitect/generation/modeling/manifest.json')
            .exists(),
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
    final engine = _modelEngine(root);
    const original = FileGenerationOperation(
      relativePath: 'lib/a.dartitect.g.dart',
      content: 'owned\n',
      rendererId: 'test.fixture',
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
      final plan = await _modelEngine(root)
          .plan(const <FileGenerationOperation>[], manageFullyGenerated: true);
      expect(plan.hasConflicts, isTrue);

      await Directory('${root.path}/.dartitect').create();
      await File('${root.path}/.dartitect/model-outputs.json')
          .writeAsString('{bad');
      await expectLater(
        _modelEngine(
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
        _modelEngine(root).apply(const <FileGenerationOperation>[
          FileGenerationOperation(
            relativePath: 'lib/new.dart',
            content: '',
            rendererId: 'test.fixture',
          ),
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

  test('unsupported namespaced manifest schemas fail closed', () async {
    for (final schema in <int>[1, 4]) {
      final root = await Directory.systemTemp.createTemp(
        'dartitect-namespaced-manifest-schema-$schema-',
      );
      addTearDown(() => root.delete(recursive: true));
      final manifest = File(
        '${root.path}/.dartitect/generation/modeling/manifest.json',
      );
      await manifest.create(recursive: true);
      final original = jsonEncode(<String, Object?>{
        'schemaVersion': schema,
        'namespace': 'modeling',
        'protocolVersion': DartitectGenerationVersions.protocol,
        'outputs': const <Object?>[],
      });
      await manifest.writeAsString(original);

      await expectLater(
        _modelEngine(
          root,
        ).plan(const <FileGenerationOperation>[], manageFullyGenerated: true),
        throwsA(
          isA<GenerationException>().having(
            (error) => error.kind,
            'kind',
            GenerationFailureKind.invalidConfiguration,
          ),
        ),
        reason: 'schema $schema',
      );
      expect(await manifest.readAsString(), original);
    }
  });

  test('schema-2 manifests migrate to mandatory renderer identities', () async {
    final root = await Directory.systemTemp.createTemp(
      'dartitect-renderer-manifest-',
    );
    addTearDown(() => root.delete(recursive: true));
    const operation = FileGenerationOperation(
      relativePath: 'lib/value.dartitect.g.dart',
      content: 'value\n',
      rendererId: 'model.value',
      ownership: GeneratedOwnership.fullyGenerated,
      sourcePath: 'lib/value.dart',
      inputSignature: 'value',
    );
    final engine = _modelEngine(root);
    await engine.apply(const <FileGenerationOperation>[
      operation,
    ], manageFullyGenerated: true);
    final manifest = File(
      '${root.path}/.dartitect/generation/modeling/manifest.json',
    );
    final legacy =
        jsonDecode(await manifest.readAsString()) as Map<String, Object?>;
    legacy['schemaVersion'] = 2;
    final entry =
        (legacy['outputs']! as List<Object?>).single as Map<String, Object?>;
    entry.remove('rendererId');
    await manifest.writeAsString(jsonEncode(legacy));

    final preview = await engine.plan(const <FileGenerationOperation>[
      operation,
    ], manageFullyGenerated: true);
    expect(preview.updates, hasLength(1));
    await engine.apply(const <FileGenerationOperation>[
      operation,
    ], manageFullyGenerated: true);

    final migrated =
        jsonDecode(await manifest.readAsString()) as Map<String, Object?>;
    expect(migrated['schemaVersion'], DartitectGenerationVersions.manifest);
    final migratedEntry =
        (migrated['outputs']! as List<Object?>).single as Map<String, Object?>;
    expect(migratedEntry['rendererId'], 'model.value');
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
        _modelEngine(root).recover(),
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

  test('unsupported namespaced journal schemas preserve residue', () async {
    for (final schema in <int>[2, 4]) {
      final root = await Directory.systemTemp.createTemp(
        'dartitect-namespaced-journal-schema-$schema-',
      );
      addTearDown(() => root.delete(recursive: true));
      final journal = File(
        '${root.path}/.dartitect/generation/modeling/journal.json',
      );
      await journal.create(recursive: true);
      final original = jsonEncode(<String, Object?>{
        'schemaVersion': schema,
        'namespace': 'modeling',
        'protocolVersion': DartitectGenerationVersions.protocol,
        'phase': 'committing',
        'entries': const <Object?>[],
        'manifest': null,
      });
      await journal.writeAsString(original);

      await expectLater(
        _modelEngine(root).recover(),
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
                <String>['.dartitect/generation/modeling/journal.json'],
              ),
        ),
      );
      expect(await journal.readAsString(), original);
    }
  });

  test('unjournaled current and legacy transactions fail closed', () async {
    for (final relative in <String>[
      '.dartitect/generation/modeling/transaction',
      '.dartitect/generation-transaction',
    ]) {
      final root = await Directory.systemTemp.createTemp(
        'dartitect-unjournaled-',
      );
      addTearDown(() => root.delete(recursive: true));
      await Directory('${root.path}/$relative').create(recursive: true);

      await expectLater(
        _modelEngine(root).plan(const <FileGenerationOperation>[]),
        throwsA(
          isA<GenerationException>()
              .having(
                (error) => error.kind,
                'kind',
                GenerationFailureKind.invalidConfiguration,
              )
              .having(
                (error) => error.recoveryPaths,
                'recovery paths',
                <String>[relative],
              ),
        ),
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

    await _modelEngine(root).recover();

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
        _modelEngine(root).recover(),
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

  test('namespaces isolate manifests and ownership sets', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-namespaces-');
    addTearDown(() => root.delete(recursive: true));
    const alpha = GenerationNamespace(
      'alpha',
      fullyGeneratedSuffix: '.alpha.g.dart',
    );
    const beta = GenerationNamespace(
      'beta',
      fullyGeneratedSuffix: '.beta.g.dart',
    );
    const alphaOperation = FileGenerationOperation(
      relativePath: 'lib/value.alpha.g.dart',
      content: 'alpha\n',
      rendererId: 'test.fixture',
      ownership: GeneratedOwnership.fullyGenerated,
      sourcePath: 'lib/value.dart',
      inputSignature: 'alpha',
    );
    const betaOperation = FileGenerationOperation(
      relativePath: 'lib/value.beta.g.dart',
      content: 'beta\n',
      rendererId: 'test.fixture',
      ownership: GeneratedOwnership.fullyGenerated,
      sourcePath: 'lib/value.dart',
      inputSignature: 'beta',
    );

    await GenerationEngine(root, namespace: alpha).apply(
      const <FileGenerationOperation>[alphaOperation],
      manageFullyGenerated: true,
    );
    await GenerationEngine(root, namespace: beta).apply(
      const <FileGenerationOperation>[betaOperation],
      manageFullyGenerated: true,
    );
    await GenerationEngine(
      root,
      namespace: alpha,
    ).apply(const <FileGenerationOperation>[], manageFullyGenerated: true);

    expect(await File('${root.path}/lib/value.alpha.g.dart').exists(), isFalse);
    expect(await File('${root.path}/lib/value.beta.g.dart').exists(), isTrue);
    expect(
      await File('${root.path}/.dartitect/generation/alpha/manifest.json')
          .exists(),
      isTrue,
    );
    expect(
      await File('${root.path}/.dartitect/generation/beta/manifest.json')
          .exists(),
      isTrue,
    );
  });

  test(
    'overlapping suffixes respect ownership from sibling manifests',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'dartitect-overlapping-namespaces-',
      );
      addTearDown(() => root.delete(recursive: true));
      const contract = FileGenerationOperation(
        relativePath: 'lib/api.contracts.dartitect.g.dart',
        content: 'contract\n',
        rendererId: 'contracts.fixture',
        ownership: GeneratedOwnership.fullyGenerated,
        sourcePath: 'contracts/api.yaml',
        inputSignature: 'contract',
      );

      await GenerationEngine(
        root,
        namespace: GenerationNamespace.contracts,
      ).apply(const <FileGenerationOperation>[
        contract,
      ], manageFullyGenerated: true);

      final clean = await _modelEngine(root)
          .plan(const <FileGenerationOperation>[], manageFullyGenerated: true);
      expect(clean.operations, isEmpty);

      await File('${root.path}/lib/unclaimed.dartitect.g.dart')
          .writeAsString('consumer\n');
      final conflicted = await _modelEngine(root)
          .plan(const <FileGenerationOperation>[], manageFullyGenerated: true);
      final conflicts = conflicted.operations
          .where(
            (operation) =>
                operation.disposition == GenerationDisposition.conflict,
          )
          .toList(growable: false);
      expect(conflicts, hasLength(1));
      expect(
        conflicts.single.operation.relativePath,
        'lib/unclaimed.dartitect.g.dart',
      );
    },
  );

  test('shared project lock serializes different namespaces', () async {
    final root = await Directory.systemTemp.createTemp(
      'dartitect-shared-lock-',
    );
    addTearDown(() => root.delete(recursive: true));
    final entered = Completer<void>();
    final release = Completer<void>();
    final first =
        GenerationEngine(
          root,
          namespace: GenerationNamespace.scaffolding,
          faultInjector: (event) async {
            if (event.point == GenerationFaultPoint.afterPersistJournal &&
                !entered.isCompleted) {
              entered.complete();
              await release.future;
            }
          },
        ).apply(const <FileGenerationOperation>[
          FileGenerationOperation(
            relativePath: 'first.txt',
            content: 'first\n',
            rendererId: 'test.fixture',
          ),
        ]);
    await entered.future;

    final second =
        GenerationEngine(
          root,
          namespace: const GenerationNamespace('secondary'),
        ).apply(const <FileGenerationOperation>[
          FileGenerationOperation(
            relativePath: 'second.txt',
            content: 'second\n',
            rendererId: 'test.fixture',
          ),
        ]);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(await File('${root.path}/second.txt').exists(), isFalse);

    release.complete();
    await Future.wait(<Future<GenerationResult>>[first, second]);
    expect(await File('${root.path}/first.txt').exists(), isTrue);
    expect(await File('${root.path}/second.txt').exists(), isTrue);
  });

  test('concurrent output bytes are preserved after staging', () async {
    final root = await Directory.systemTemp.createTemp(
      'dartitect-concurrent-output-',
    );
    addTearDown(() => root.delete(recursive: true));
    FileGenerationOperation model(String content) => FileGenerationOperation(
      relativePath: 'lib/value.dartitect.g.dart',
      content: content,
      rendererId: 'test.fixture',
      ownership: GeneratedOwnership.fullyGenerated,
      sourcePath: 'lib/value.dart',
      inputSignature: content,
    );
    await _modelEngine(root).apply(<FileGenerationOperation>[
      model('v1\n'),
    ], manageFullyGenerated: true);
    var changed = false;
    final engine = GenerationEngine(
      root,
      namespace: GenerationNamespace.modeling,
      faultInjector: (event) async {
        if (!changed &&
            event.point == GenerationFaultPoint.afterStageOutput &&
            event.path == 'lib/value.dartitect.g.dart') {
          changed = true;
          await File('${root.path}/lib/value.dartitect.g.dart')
              .writeAsString('consumer\n');
        }
      },
    );

    await expectLater(
      engine.apply(<FileGenerationOperation>[
        model('v2\n'),
      ], manageFullyGenerated: true),
      throwsA(
        isA<GenerationException>().having(
          (error) => error.kind,
          'kind',
          GenerationFailureKind.recovery,
        ),
      ),
    );

    expect(changed, isTrue);
    expect(
      await File('${root.path}/lib/value.dartitect.g.dart').readAsString(),
      'consumer\n',
    );
    expect(
      await File('${root.path}/.dartitect/generation/modeling/journal.json')
          .exists(),
      isTrue,
    );
  });

  test(
    'verified RC3 manifest migrates atomically to modeling namespace',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'dartitect-rc3-manifest-',
      );
      addTearDown(() => root.delete(recursive: true));
      const operation = FileGenerationOperation(
        relativePath: 'lib/user.dartitect.g.dart',
        content: 'owned\n',
        rendererId: 'model.value',
        ownership: GeneratedOwnership.fullyGenerated,
        sourcePath: 'lib/user.dart',
        rendererVersion: DartitectGenerationVersions.modelRenderer,
        semanticSchemaVersion:
            DartitectGenerationVersions.modelingSemanticSchema,
        inputSignature: 'semantic',
      );
      await File('${root.path}/lib/user.dartitect.g.dart')
          .create(recursive: true)
          .then((file) => file.writeAsString(operation.content));
      await _writeLegacyManifest(root, operation);
      final legacy = File('${root.path}/.dartitect/model-outputs.json');
      final engine = _modelEngine(root);

      final preview = await engine.plan(const <FileGenerationOperation>[
        operation,
      ], manageFullyGenerated: true);
      expect(preview.migratesLegacyOwnership, isTrue);
      expect(preview.hasChanges, isTrue);
      expect(preview.operations.single.disposition, GenerationDisposition.noOp);
      await engine.apply(const <FileGenerationOperation>[
        operation,
      ], manageFullyGenerated: true);

      expect(await legacy.exists(), isFalse);
      final migrated = jsonDecode(
        await File('${root.path}/.dartitect/generation/modeling/manifest.json')
            .readAsString(),
      ) as Map<String, Object?>;
      expect(migrated['schemaVersion'], DartitectGenerationVersions.manifest);
      expect(migrated['namespace'], 'modeling');
      expect(migrated['protocolVersion'], DartitectGenerationVersions.protocol);
      final entry =
          (migrated['outputs']! as List<Object?>).single
              as Map<String, Object?>;
      expect(
        entry['rendererVersion'],
        DartitectGenerationVersions.modelRenderer,
      );
      expect(
        entry['semanticSchemaVersion'],
        DartitectGenerationVersions.modelingSemanticSchema,
      );
      expect(entry['rendererId'], 'model.value');
      expect(entry.containsKey('generatorVersion'), isFalse);
    },
  );

  test(
    'fault during RC3 adoption restores legacy ownership and bytes',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'dartitect-rc3-fault-',
      );
      addTearDown(() => root.delete(recursive: true));
      const legacyOperation = FileGenerationOperation(
        relativePath: 'lib/user.dartitect.g.dart',
        content: 'legacy\n',
        rendererId: 'model.value',
        ownership: GeneratedOwnership.fullyGenerated,
        sourcePath: 'lib/user.dart',
        inputSignature: 'semantic',
      );
      const desired = FileGenerationOperation(
        relativePath: 'lib/user.dartitect.g.dart',
        content: 'desired\n',
        rendererId: 'model.value',
        ownership: GeneratedOwnership.fullyGenerated,
        sourcePath: 'lib/user.dart',
        inputSignature: 'semantic',
      );
      final output = File('${root.path}/lib/user.dartitect.g.dart');
      await output.create(recursive: true);
      await output.writeAsString(legacyOperation.content);
      await _writeLegacyManifest(root, legacyOperation);
      var injected = false;
      final engine = GenerationEngine(
        root,
        namespace: GenerationNamespace.modeling,
        faultInjector: (event) {
          if (!injected &&
              event.point == GenerationFaultPoint.afterReplacement &&
              event.path == desired.relativePath) {
            injected = true;
            throw StateError('interrupt RC3 adoption');
          }
        },
      );

      await expectLater(
        engine.apply(const <FileGenerationOperation>[
          desired,
        ], manageFullyGenerated: true),
        throwsA(isA<GenerationException>()),
      );

      expect(injected, isTrue);
      expect(await output.readAsString(), legacyOperation.content);
      expect(
        await File('${root.path}/.dartitect/model-outputs.json').exists(),
        isTrue,
      );
      expect(
        await File('${root.path}/.dartitect/generation/modeling/manifest.json')
            .exists(),
        isFalse,
      );
    },
  );

  test('RC3 migration rejects unproven current bytes without writes', () async {
    final root = await Directory.systemTemp.createTemp(
      'dartitect-rc3-mismatch-',
    );
    addTearDown(() => root.delete(recursive: true));
    const operation = FileGenerationOperation(
      relativePath: 'lib/user.dartitect.g.dart',
      content: 'owned\n',
      rendererId: 'model.value',
      ownership: GeneratedOwnership.fullyGenerated,
      sourcePath: 'lib/user.dart',
      inputSignature: 'semantic',
    );
    final output = File('${root.path}/lib/user.dartitect.g.dart');
    await output.create(recursive: true);
    await output.writeAsString(operation.content);
    await _writeLegacyManifest(root, operation);
    await output.writeAsString('consumer\n');

    await expectLater(
      _modelEngine(root).apply(const <FileGenerationOperation>[
        operation,
      ], manageFullyGenerated: true),
      throwsA(
        isA<GenerationException>().having(
          (error) => error.recoveryPaths,
          'recovery paths',
          <String>['lib/user.dartitect.g.dart'],
        ),
      ),
    );
    expect(await output.readAsString(), 'consumer\n');
    expect(
      await File('${root.path}/.dartitect/model-outputs.json').exists(),
      isTrue,
    );
    expect(
      await File('${root.path}/.dartitect/generation/modeling/manifest.json')
          .exists(),
      isFalse,
    );
  });

  test('legacy ownership from a non-RC3 cohort fails closed', () async {
    final root = await Directory.systemTemp.createTemp(
      'dartitect-non-rc3-manifest-',
    );
    addTearDown(() => root.delete(recursive: true));
    const operation = FileGenerationOperation(
      relativePath: 'lib/user.dartitect.g.dart',
      content: 'owned\n',
      rendererId: 'model.value',
      ownership: GeneratedOwnership.fullyGenerated,
      sourcePath: 'lib/user.dart',
      inputSignature: 'semantic',
    );
    await File('${root.path}/lib/user.dartitect.g.dart')
        .create(recursive: true)
        .then((file) => file.writeAsString(operation.content));
    await _writeLegacyManifest(root, operation);
    final legacy = File('${root.path}/.dartitect/model-outputs.json');
    final decoded =
        jsonDecode(await legacy.readAsString()) as Map<String, Object?>;
    final entry =
        (decoded['outputs']! as List<Object?>).single as Map<String, Object?>;
    entry['generatorVersion'] = '1.0.0-rc.2';
    await legacy.writeAsString(jsonEncode(decoded));

    await expectLater(
      _modelEngine(root).plan(const <FileGenerationOperation>[
        operation,
      ], manageFullyGenerated: true),
      throwsA(
        isA<GenerationException>().having(
          (error) => error.kind,
          'kind',
          GenerationFailureKind.invalidConfiguration,
        ),
      ),
    );
    entry['generatorVersion'] = '1.0.0-rc.3';
    entry['inputSchemaVersion'] = 3;
    await legacy.writeAsString(jsonEncode(decoded));
    await expectLater(
      _modelEngine(root).plan(const <FileGenerationOperation>[
        operation,
      ], manageFullyGenerated: true),
      throwsA(
        isA<GenerationException>().having(
          (error) => error.kind,
          'kind',
          GenerationFailureKind.invalidConfiguration,
        ),
      ),
    );
    expect(await legacy.exists(), isTrue);
  });

  test('journal v3 restores namespaced transaction bytes', () async {
    final root = await Directory.systemTemp.createTemp(
      'dartitect-recovery-v3-',
    );
    addTearDown(() => root.delete(recursive: true));
    const before = 'before\n';
    const after = 'after\n';
    await File('${root.path}/lib/value.dart')
        .create(recursive: true)
        .then((file) => file.writeAsString(after));
    final transaction = Directory(
      '${root.path}/.dartitect/generation/modeling/transaction',
    );
    await File('${transaction.path}/backup/lib/value.dart')
        .create(recursive: true)
        .then((file) => file.writeAsString(before));
    await File('${root.path}/.dartitect/generation/modeling/journal.json')
        .create(recursive: true)
        .then(
          (file) => file.writeAsString(
            jsonEncode(<String, Object?>{
              'schemaVersion': DartitectGenerationVersions.journal,
              'namespace': 'modeling',
              'protocolVersion': DartitectGenerationVersions.protocol,
              'phase': 'committing',
              'entries': <Object?>[
                _journalEntry('lib/value.dart', 'update', before, after),
              ],
              'manifest': null,
            }),
          ),
        );

    await _modelEngine(root).recover();

    expect(await File('${root.path}/lib/value.dart').readAsString(), before);
    expect(await transaction.exists(), isFalse);
  });

  test('fault matrix recovers or preserves one complete generation', () async {
    for (final point in GenerationFaultPoint.values) {
      final root = await Directory.systemTemp.createTemp(
        'dartitect-fault-${point.name}-',
      );
      addTearDown(() => root.delete(recursive: true));
      FileGenerationOperation model(String content) => FileGenerationOperation(
        relativePath: 'lib/user.dartitect.g.dart',
        content: content,
        rendererId: 'test.fixture',
        ownership: GeneratedOwnership.fullyGenerated,
        sourcePath: 'lib/user.dart',
        inputSignature: content,
      );
      await _modelEngine(root).apply(<FileGenerationOperation>[
        model('v1\n'),
      ], manageFullyGenerated: true);
      var injected = false;
      final engine = GenerationEngine(
        root,
        namespace: GenerationNamespace.modeling,
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

      final retry = _modelEngine(root);
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
        await File('${root.path}/.dartitect/generation/modeling/manifest.json')
            .readAsString(),
      ) as Map<String, Object?>;
      expect(manifest['outputs'], hasLength(1), reason: point.name);
      expect(
        await File('${root.path}/.dartitect/generation/modeling/journal.json')
            .exists(),
        isFalse,
        reason: point.name,
      );
      expect(
        await Directory(
          '${root.path}/.dartitect/generation/modeling/transaction',
        ).exists(),
        isFalse,
        reason: point.name,
      );
    }
  });
}

GenerationEngine _modelEngine(Directory root) =>
    GenerationEngine(root, namespace: GenerationNamespace.modeling);

Future<void> _writeLegacyManifest(
  Directory root,
  FileGenerationOperation operation,
) async {
  final manifest = File('${root.path}/.dartitect/model-outputs.json');
  await manifest.create(recursive: true);
  final encoded = const JsonEncoder.withIndent('  ').convert(<String, Object?>{
    'schemaVersion': 1,
    'generator': 'dartitect model',
    'outputs': <Object?>[
      <String, Object?>{
        'path': operation.relativePath,
        'source': operation.sourcePath,
        'generatorVersion': '1.0.0-rc.3',
        'inputSchemaVersion': 4,
        'inputDigest': _canonicalDigest(operation.inputSignature!),
        'outputDigest': _canonicalDigest(operation.content),
      },
    ],
  });
  await manifest.writeAsString('$encoded\n');
}

String _canonicalDigest(String value) {
  final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final canonical = normalized.endsWith('\n') ? normalized : '$normalized\n';
  return sha256.convert(utf8.encode(canonical)).toString();
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
