import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'dependency_snippets.dart';

void main() {
  final root = Directory.current.absolute;

  test('emits only selected direct packages with canonical descriptors', () {
    final output = buildDependencySnippet(root, const <String>[
      'dartitect_flutter',
    ]);
    expect(_packages(output), const <String>['dartitect_flutter']);
    expect(output, contains('url: https://github.com/ftr-tuta/dartitect.git'));
    expect(output, contains('path: packages/dartitect_flutter'));
    expect(output, contains("tag_pattern: 'v{{version}}'"));
    expect(output, contains('version: 1.1.0'));
    expect(output, isNot(contains('dependency_overrides')));
  });

  test('supports all five official profiles', () {
    expect(dependencySnippetProfiles.keys, <String>{
      'core',
      'flutter',
      'drift',
      'objectbox',
      'tooling',
    });
    for (final profile in dependencySnippetProfiles.values) {
      expect(_packages(buildDependencySnippet(root, profile)), isNotEmpty);
    }
  });

  test('supports the complete twenty-five-package cohort', () {
    final contract = jsonDecode(
      File('${root.path}/tool/package_release_contract.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    final packages = contract['packages']! as Map<String, Object?>;
    expect(
      _packages(buildDependencySnippet(root, packages.keys)).toSet(),
      hasLength(25),
    );
  });

  test('rejects packages outside the public cohort', () {
    expect(
      () => buildDependencySnippet(root, const <String>['not_dartitect']),
      throwsArgumentError,
    );
  });
}

List<String> _packages(String yaml) => RegExp(
  r'^  (dartitect(?:_[a-z0-9_]+)?):$',
  multiLine: true,
).allMatches(yaml).map((match) => match.group(1)!).toList();
