import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'git_dependency_overrides.dart';

void main() {
  final root = Directory.current.absolute;

  test('includes the transitive core package for dartitect_flutter', () {
    final output = buildGitDependencyOverrides(
      root,
      const <String>['dartitect_flutter'],
      repository: 'https://example.invalid/dartitect.git',
      ref: 'v1.0.0-rc.8',
    );
    expect(_packages(output), <String>['dartitect', 'dartitect_flutter']);
    expect(output, contains('ref: v1.0.0-rc.8'));
  });

  test('computes deeper adapter closure in publication order', () {
    final output = buildGitDependencyOverrides(
      root,
      const <String>['dartitect_dio'],
      repository: 'file:///tmp/dartitect.git',
      ref: 'candidate-tag',
    );
    expect(_packages(output), <String>[
      'dartitect',
      'dartitect_observability',
      'dartitect_transfer',
      'dartitect_dio',
    ]);
  });

  test(
    'supports any combination of the complete twenty-five-package cohort',
    () {
      final contract = jsonDecode(
        File('${root.path}/tool/package_release_contract.json')
            .readAsStringSync(),
      ) as Map<String, Object?>;
      final packages = contract['packages']! as Map<String, Object?>;
      final names = packages.keys.toSet();
      final output = buildGitDependencyOverrides(
        root,
        names,
        repository: 'https://example.invalid/dartitect.git',
        ref: 'v1.0.0-rc.8',
      );
      expect(_packages(output).toSet(), hasLength(25));
    },
  );

  test('rejects packages outside the public cohort', () {
    expect(
      () => buildGitDependencyOverrides(
        root,
        const <String>['not_dartitect'],
        repository: 'https://example.invalid/dartitect.git',
        ref: 'v1.0.0-rc.8',
      ),
      throwsArgumentError,
    );
  });
}

List<String> _packages(String yaml) => RegExp(
  r'^  (dartitect(?:_[a-z]+)*):$',
  multiLine: true,
).allMatches(yaml).map((match) => match.group(1)!).toList();
