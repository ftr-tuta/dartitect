import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('accepts classified complete documentation', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    final result = await fixture.check();

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('rejects an unclassified document', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await File('${fixture.root.path}/docs/unclassified.md')
        .writeAsString('# Unclassified\n\nContent.\n');

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('documentation file is not classified'));
  });

  test('rejects a truncated Markdown fence', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.document.writeAsString(
      '# Documentation\n\n```dart\nvoid main() {}\n',
    );

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('unbalanced Markdown code fence'));
  });

  test('rejects a broken Markdown link', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.document.writeAsString(
      '# Documentation\n\nRead [missing](missing.md).\n',
    );

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('broken local link missing.md'));
  });

  test('rejects a broken AsciiDoc link or include', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.addCurrent('docs/include-test.adoc');
    await File('${fixture.root.path}/docs/include-test.adoc')
        .writeAsString('= Include test\n\ninclude::missing.adoc[]\n');

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(
      result.stderr,
      contains('broken AsciiDoc link/include missing.adoc'),
    );
  });

  test('rejects an empty section and placeholder', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.document.writeAsString(
      '# Documentation\n\nContent.\n\n## Missing\n\nTODO\n',
    );

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('unfinished placeholder'));
  });

  test('rejects an empty final section', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.document.writeAsString(
      '# Documentation\n\nContent.\n\n## Empty\n',
    );

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('empty section "## Empty"'));
  });
}

final class _Fixture {
  const _Fixture(this.root);

  final Directory root;

  File get contract => File('${root.path}/tool/documentation_contract.json');
  File get document => File('${root.path}/docs/README.md');

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp('public-docs-contract-');
    await Directory('${root.path}/tool').create(recursive: true);
    await Directory('${root.path}/docs').create(recursive: true);
    final fixture = _Fixture(root);
    await fixture.contract.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(_contract())}\n',
    );
    await fixture.document.writeAsString(
      '# Documentation\n\nComplete content.\n',
    );
    return fixture;
  }

  Future<void> addCurrent(String path) async {
    final value = jsonDecode(await contract.readAsString());
    final object = value as Map<String, Object?>;
    final classifications = object['classifications']! as Map<String, Object?>;
    (classifications['current']! as List<Object?>).add(path);
    await contract.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(object)}\n',
    );
  }

  Future<ProcessResult> check() =>
      Process.run(Platform.resolvedExecutable, <String>[
        '${Directory.current.path}/tool/check_public_docs.dart',
        '--root',
        root.path,
        '--content-only',
      ]);

  Future<void> dispose() => root.delete(recursive: true);

  static Map<String, Object?> _contract() => <String, Object?>{
    'schemaVersion': 1,
    'roots': <String>['.', 'docs', 'packages', 'examples', '.agents/skills'],
    'classifications': <String, Object?>{
      'current': <String>['docs/README.md'],
      'migration-entry': <String>[],
      'historical': <String>[],
      'generated': <String>[],
    },
    'excluded': <String>[],
    'activeReleaseCandidateExclusions': <String>[],
  };
}
