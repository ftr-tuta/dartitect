import 'dart:io';

import 'package:test/test.dart';

import 'release_audit.dart';

const _canonicalEnvironment = <String, String>{
  'GIT_AUTHOR_NAME': 'ftr',
  'GIT_AUTHOR_EMAIL': 'ftr@tuta.com',
  'GIT_COMMITTER_NAME': 'ftr',
  'GIT_COMMITTER_EMAIL': 'ftr@tuta.com',
};

void main() {
  test('accepts canonical authorship for the selected history', () async {
    final repository = await _GitRepository.create();
    addTearDown(repository.dispose);
    await repository.commit('canonical');

    await verifyCanonicalAuthors(repository.root, _options());
  });

  test('accepts the explicitly mapped GitHub squash author', () async {
    final repository = await _GitRepository.create();
    addTearDown(repository.dispose);
    await repository.writeMailmap(
      'ftr <ftr@tuta.com> ftr-tuta <ftr@tuta.com>\n',
    );
    await repository.commit(
      'GitHub squash',
      environment: const <String, String>{
        'GIT_AUTHOR_NAME': 'ftr-tuta',
        'GIT_AUTHOR_EMAIL': 'ftr@tuta.com',
        'GIT_COMMITTER_NAME': 'GitHub',
        'GIT_COMMITTER_EMAIL': 'noreply@github.com',
      },
    );

    await verifyCanonicalAuthors(repository.root, _options());
  });

  test('rejects a noncanonical author', () async {
    final repository = await _GitRepository.create();
    addTearDown(repository.dispose);
    await repository.commit(
      'invalid',
      environment: const <String, String>{
        'GIT_AUTHOR_NAME': 'Someone Else',
        'GIT_AUTHOR_EMAIL': 'someone@example.com',
        'GIT_COMMITTER_NAME': 'Someone Else',
        'GIT_COMMITTER_EMAIL': 'someone@example.com',
      },
    );

    await expectLater(
      verifyCanonicalAuthors(repository.root, _options()),
      throwsA(isA<StateError>()),
    );
  });

  test('audits a PR head instead of its synthetic merge commit', () async {
    final repository = await _GitRepository.create();
    addTearDown(repository.dispose);
    await repository.commit('base');
    final head = await repository.commit('pull request head');
    await repository.syntheticMerge(
      authorName: 'GitHub',
      authorEmail: 'noreply@github.com',
    );

    await verifyCanonicalAuthors(
      repository.root,
      _options(authorRevision: head),
    );
  });

  test('excludes the synthetic merge commit for a merge group', () async {
    final repository = await _GitRepository.create();
    addTearDown(repository.dispose);
    await repository.commit('base');
    await repository.commit('queued pull request');
    await repository.syntheticMerge(
      authorName: 'GitHub',
      authorEmail: 'noreply@github.com',
    );

    await verifyCanonicalAuthors(
      repository.root,
      _options(excludeMergeCommits: true),
    );
    await expectLater(
      verifyCanonicalAuthors(repository.root, _options()),
      throwsA(isA<StateError>()),
    );
  });

  test('rejects a nonexistent author revision', () async {
    final repository = await _GitRepository.create();
    addTearDown(repository.dispose);
    await repository.commit('base');

    await expectLater(
      verifyCanonicalAuthors(
        repository.root,
        _options(authorRevision: '0000000000000000000000000000000000000000'),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('rejects unknown, malformed, and duplicate arguments', () {
    expect(
      () => ReleaseAuditOptions.parse(const <String>['--unknown']),
      throwsArgumentError,
    );
    expect(
      () => ReleaseAuditOptions.parse(const <String>['--author-revision=abc']),
      throwsArgumentError,
    );
    expect(
      () => ReleaseAuditOptions.parse(const <String>['--docs', '--docs']),
      throwsArgumentError,
    );
  });
}

ReleaseAuditOptions _options({
  String? authorRevision,
  bool excludeMergeCommits = false,
}) => ReleaseAuditOptions(
  docs: false,
  publishDryRun: false,
  authorRevision: authorRevision,
  excludeMergeCommits: excludeMergeCommits,
);

final class _GitRepository {
  _GitRepository(this.root);

  final Directory root;

  static Future<_GitRepository> create() async {
    final root = await Directory.systemTemp.createTemp(
      'dartitect-release-audit-test-',
    );
    final repository = _GitRepository(root);
    await repository._git(const <String>['init', '--quiet']);
    return repository;
  }

  Future<void> writeMailmap(String contents) async {
    await File('${root.path}/.mailmap').writeAsString(contents);
  }

  Future<String> commit(
    String message, {
    Map<String, String> environment = _canonicalEnvironment,
  }) async {
    await File('${root.path}/fixture.txt').writeAsString('$message\n');
    await _git(const <String>['add', 'fixture.txt']);
    await _git(<String>[
      'commit',
      '--quiet',
      '-m',
      message,
    ], environment: environment);
    return _gitOutput(const <String>['rev-parse', 'HEAD']);
  }

  Future<void> syntheticMerge({
    required String authorName,
    required String authorEmail,
  }) async {
    final head = await _gitOutput(const <String>['rev-parse', 'HEAD']);
    final parent = await _gitOutput(const <String>['rev-parse', 'HEAD^']);
    final tree = await _gitOutput(const <String>['rev-parse', 'HEAD^{tree}']);
    final merge = await _gitOutput(
      <String>[
        'commit-tree',
        tree,
        '-p',
        head,
        '-p',
        parent,
        '-m',
        'synthetic merge',
      ],
      environment: <String, String>{
        'GIT_AUTHOR_NAME': authorName,
        'GIT_AUTHOR_EMAIL': authorEmail,
        'GIT_COMMITTER_NAME': authorName,
        'GIT_COMMITTER_EMAIL': authorEmail,
      },
    );
    await _git(<String>['reset', '--quiet', '--hard', merge]);
  }

  Future<void> dispose() => root.delete(recursive: true);

  Future<void> _git(
    List<String> arguments, {
    Map<String, String>? environment,
  }) async {
    final result = await Process.run(
      'git',
      arguments,
      workingDirectory: root.path,
      environment: environment,
      includeParentEnvironment: true,
    );
    if (result.exitCode != 0) {
      throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
    }
  }

  Future<String> _gitOutput(
    List<String> arguments, {
    Map<String, String>? environment,
  }) async {
    final result = await Process.run(
      'git',
      arguments,
      workingDirectory: root.path,
      environment: environment,
      includeParentEnvironment: true,
    );
    if (result.exitCode != 0) {
      throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
    }
    return (result.stdout as String).trim();
  }
}
