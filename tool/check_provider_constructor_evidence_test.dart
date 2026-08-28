import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'check_provider_constructor_evidence.dart';

void main() {
  test('checked ObjectBox 5.3.2 evidence is complete', () async {
    final errors = await checkProviderConstructorEvidence(Directory.current);

    expect(errors, isEmpty);
  });

  test('global traditional constructor permission fails closed', () async {
    final fixture = await _EvidenceFixture.create();
    addTearDown(fixture.dispose);
    final registry = fixture.registry;
    final policy = registry['policy']! as Map<String, Object?>;
    policy['traditionalConstructor'] = 'allowed';
    await fixture.writeRegistry(registry);

    final errors = await checkProviderConstructorEvidence(fixture.root);

    expect(
      errors,
      contains('Provider constructor default policy is not fail-closed.'),
    );
  });

  test(
    'changed provider version or evidence bytes invalidate exception',
    () async {
      final fixture = await _EvidenceFixture.create();
      addTearDown(fixture.dispose);
      final registry = fixture.registry;
      final entries = registry['entries']! as List<Object?>;
      final entry = entries.single! as Map<String, Object?>;
      entry['generatorVersion'] = '5.3.3';
      await fixture.writeRegistry(registry);
      await File(
        '${fixture.root.path}/tool/provider_constructor_evidence/'
        'objectbox_5_3_2_primary.failure.txt',
      ).writeAsString('tampered');

      final errors = await checkProviderConstructorEvidence(fixture.root);

      expect(
        errors,
        contains('ObjectBox constructor decision or exact versions changed.'),
      );
      expect(
        errors,
        contains(
          'Evidence digest mismatch: '
          'tool/provider_constructor_evidence/'
          'objectbox_5_3_2_primary.failure.txt.',
        ),
      );
    },
  );

  test('traversal cannot substitute provider evidence', () async {
    final fixture = await _EvidenceFixture.create();
    addTearDown(fixture.dispose);
    final registry = fixture.registry;
    final entries = registry['entries']! as List<Object?>;
    final entry = entries.single! as Map<String, Object?>;
    final candidate = entry['primaryCandidate']! as Map<String, Object?>;
    candidate['path'] = '../outside.dart';
    await fixture.writeRegistry(registry);

    final errors = await checkProviderConstructorEvidence(fixture.root);

    expect(errors, contains('Evidence path is unsafe: ../outside.dart.'));
  });
}

final class _EvidenceFixture {
  _EvidenceFixture(this.root);

  final Directory root;

  static const paths = <String>[
    'tool/provider_constructor_evidence.json',
    'tool/provider_constructor_evidence/objectbox_5_3_2_primary.dart.fixture',
    'tool/provider_constructor_evidence/objectbox_5_3_2_primary.failure.txt',
    'tool/objectbox_native_fixture/pubspec.yaml',
    'tool/objectbox_native_fixture/pubspec.lock',
    'tool/objectbox_native_fixture/lib/fixture_entity.dart',
    'tool/objectbox_native_fixture/lib/objectbox.g.dart',
    'tool/objectbox_native_fixture/lib/objectbox-model.json',
    'tool/objectbox_native_fixture/test/native_store_test.dart',
  ];

  static Future<_EvidenceFixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'provider-constructor-evidence-',
    );
    for (final path in paths) {
      final target = File('${root.path}/$path');
      await target.parent.create(recursive: true);
      await File('${Directory.current.path}/$path').copy(target.path);
    }
    return _EvidenceFixture(root);
  }

  Map<String, Object?> get registry => jsonDecode(
    File('${root.path}/tool/provider_constructor_evidence.json')
        .readAsStringSync(),
  ) as Map<String, Object?>;

  Future<void> writeRegistry(Map<String, Object?> value) => File(
    '${root.path}/tool/provider_constructor_evidence.json',
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(value)}\n');

  Future<void> dispose() => root.delete(recursive: true);
}
