import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Resolves and runs all consumer canaries from one annotated Git tag.
Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final workspace = File.fromUri(Platform.script).parent.parent.absolute;
  final status = await _run(workspace, 'git', const <String>[
    'status',
    '--porcelain=v1',
    '--untracked-files=all',
  ]);
  if (status.stdout.trim().isNotEmpty) {
    throw StateError('Git-tag canaries require a clean release tree.');
  }
  final tag = await _resolveAnnotatedTag(workspace, options);
  final contract = _object(
    jsonDecode(
      File('${workspace.path}/tool/canaries/canary_contract.json')
          .readAsStringSync(),
    ),
  );
  final release = _object(
    jsonDecode(
      File('${workspace.path}/tool/package_release_contract.json')
          .readAsStringSync(),
    ),
  );
  final cohort = _object(release['workspaceCohort']);
  final installation = _object(contract['gitInstallation']);
  final canonicalRepository = installation['repository'];
  if (contract['schemaVersion'] != 4 ||
      contract['workspaceVersion'] != cohort['version'] ||
      canonicalRepository is! String ||
      options.ref != cohort['derivedTag']) {
    throw StateError('Git tag and canary release cohorts differ.');
  }
  final gitEnvironment = gitCanaryRepositoryRedirectEnvironment(
    canonicalRepository: canonicalRepository,
    candidateRepository: options.repository,
    inheritedEnvironment: Platform.environment,
  );
  final temporary = await Directory.systemTemp.createTemp(
    'dartitect-git-tag-canaries-',
  );
  final receipts = <Map<String, Object?>>[];
  try {
    for (final canary in _objects(contract['canaries'])) {
      receipts.add(
        await _runCanary(
          workspace: workspace,
          temporary: temporary,
          options: options,
          tag: tag,
          releaseVersion: cohort['version']! as String,
          dependencyOrder: _strings(release['dependencyOrder']),
          contract: canary,
          canonicalRepository: canonicalRepository,
          gitEnvironment: gitEnvironment,
        ),
      );
    }
    final receiptDirectory = Directory(
      '${workspace.path}/build/git-canary-receipts',
    );
    await receiptDirectory.create(recursive: true);
    final receipt = File(
      '${receiptDirectory.path}/${options.ref}-${tag.commit}.json',
    );
    await receipt.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{'schemaVersion': 1, 'workspaceVersion': cohort['version'], 'channel': cohort['channel'], 'repository': options.repository, 'ref': options.ref, 'localDisposableTag': true, 'annotatedTagObject': tag.object, 'sourceCommit': tag.commit, 'packageSource': 'git', 'localPathDependencies': false, 'registryDartitectDependencies': false, 'canaries': receipts, 'result': 'PASS', 'recordedAtUtc': DateTime.now().toUtc().toIso8601String()})}\n',
      flush: true,
    );
    stdout
      ..writeln('Git-tag canaries passed for ${options.ref} at ${tag.commit}.')
      ..writeln('Receipt: ${receipt.path}');
  } finally {
    if (options.keepArtifacts) {
      stderr.writeln('Git canary artifacts retained at ${temporary.path}.');
    } else if (temporary.existsSync()) {
      await temporary.delete(recursive: true);
    }
  }
}

Future<Map<String, Object?>> _runCanary({
  required Directory workspace,
  required Directory temporary,
  required _Options options,
  required _Tag tag,
  required String releaseVersion,
  required List<String> dependencyOrder,
  required Map<String, Object?> contract,
  required String canonicalRepository,
  required Map<String, String> gitEnvironment,
}) async {
  final id = contract['id']! as String;
  final source = Directory('${workspace.path}/${contract['source']}');
  final pubspec = File('${workspace.path}/${contract['pubspec']}');
  final consumer = Directory('${temporary.path}/$id');
  await _copyConsumer(source, consumer);
  final renderedPubspec = _renderGitDependencies(
    pubspec.readAsStringSync(),
    repository: canonicalRepository,
    version: releaseVersion,
  );
  if (RegExp(
    r'^dependency_overrides:',
    multiLine: true,
  ).hasMatch(renderedPubspec)) {
    throw StateError('${contract['pubspec']} already contains overrides.');
  }
  await File('${consumer.path}/pubspec.yaml')
      .writeAsString(renderedPubspec, flush: true);

  stdout.writeln('\nValidating Git-tag canary: $id');
  final commands = <Map<String, Object?>>[];
  Future<void> run(
    String executable,
    List<String> arguments, {
    Map<String, String> extraEnvironment = const <String, String>{},
    String? receiptCommand,
  }) async {
    final command = receiptCommand ?? '$executable ${arguments.join(' ')}';
    stdout.writeln('> $command');
    final stopwatch = Stopwatch()..start();
    final result = await _run(
      consumer,
      executable,
      arguments,
      environment: <String, String>{
        ...Platform.environment,
        ...gitEnvironment,
        ...extraEnvironment,
      },
      timeout: const Duration(minutes: 15),
    );
    stopwatch.stop();
    commands.add(<String, Object?>{
      'command': command,
      'exitCode': result.exitCode,
      'durationMilliseconds': stopwatch.elapsedMilliseconds,
    });
  }

  await run('flutter', const <String>['pub', 'get']);
  switch (id) {
    case 'modeling':
      await run('dart', const <String>[
        'run',
        'dartitect_cli:dartitect',
        'model',
        'sync',
        '--apply',
      ]);
      await run('dart', const <String>[
        'run',
        'dartitect_cli:dartitect',
        'model',
        'check',
      ]);
      await run('dart', const <String>[
        'run',
        'dartitect_cli:dartitect',
        'verify',
        '--json',
      ]);
      await run('dart', const <String>['analyze']);
      await run('dart', const <String>['test']);
      await run('dart', const <String>['test', '--platform', 'chrome']);
    case 'thin_consumer':
      _assertConsumerOwnedSeams(consumer);
      await run('dart', const <String>[
        'run',
        'dartitect_cli:dartitect',
        'wiring',
        'sync',
        '--dry-run',
        '--json',
      ]);
      await run('flutter', const <String>['analyze']);
      await run('flutter', const <String>['test']);
      await run('flutter', const <String>['build', 'web', '--release']);
    case 'large_consumer':
      await run('dart', const <String>[
        'run',
        'tool/materialize_large_consumer.dart',
        '--fresh',
      ]);
      await run('dart', const <String>[
        'run',
        'dartitect_cli:dartitect',
        'contracts',
        'sync',
        'contracts/app_api.json',
        '--apply',
      ]);
      await run('dart', const <String>[
        'run',
        'tool/verify_large_preview.dart',
      ]);
      await run('dart', const <String>[
        'run',
        'dartitect_cli:dartitect',
        'wiring',
        'sync',
        '--apply',
        '--json',
      ]);
      await run('dart', const <String>[
        'run',
        'dartitect_cli:dartitect',
        'wiring',
        'sync',
        '--dry-run',
        '--json',
      ]);
      await run('dart', const <String>[
        'run',
        'dartitect_cli:dartitect',
        'fleet',
        'inventory',
        '.',
        '--json',
      ]);
      await run('flutter', const <String>['analyze']);
      await run('flutter', const <String>['analyze']);
      await run('flutter', const <String>['test']);
      await run('flutter', const <String>['build', 'web', '--release']);
      await run('flutter', const <String>['build', 'web', '--release']);
      await run('flutter', const <String>['build', 'linux', '--release']);
      if (gitCanaryRunsStableUpgrade(releaseVersion)) {
        await run('dart', <String>[
          'run',
          'dartitect_cli:dartitect',
          'fleet',
          'upgrade',
          '.',
          '--to=$releaseVersion',
          '--apply',
          '--json',
        ]);
      }
    case 'minimal':
      await run('dart', const <String>[
        'run',
        'dartitect_cli:dartitect',
        'model',
        'sync',
        '--apply',
      ]);
      await run('dart', const <String>[
        'run',
        'dartitect_cli:dartitect',
        'model',
        'check',
      ]);
      await run('flutter', const <String>['analyze']);
      await run('flutter', const <String>['test']);
    case 'offline_first':
      await run('dart', const <String>[
        'run',
        'build_runner',
        'build',
        '--delete-conflicting-outputs',
      ]);
      await run('flutter', const <String>['analyze']);
      await run('flutter', const <String>[
        'test',
        'test/offline_first_session_test.dart',
        'test/widget_test.dart',
      ]);
      await run(
        'flutter',
        const <String>[
          'test',
          'test/native_objectbox_workload_test.dart',
          'test/drift_objectbox_bounded_contexts_test.dart',
        ],
        extraEnvironment: _nativeObjectBoxEnvironment(workspace),
        receiptCommand:
            'DARTITECT_NATIVE_OBJECTBOX=1 flutter test '
            'test/native_objectbox_workload_test.dart '
            'test/drift_objectbox_bounded_contexts_test.dart',
      );
      await run('flutter', <String>[
        'build',
        _hostDesktopTarget(),
      ], receiptCommand: 'flutter build host-desktop');
    case 'drift_provider':
      await run('dart', const <String>[
        'run',
        'build_runner',
        'build',
        '--delete-conflicting-outputs',
      ]);
      await run('dart', const <String>['analyze']);
      await run('dart', const <String>['test']);
    case 'native_capabilities':
      await run('flutter', const <String>['analyze']);
      await run('flutter', const <String>['test']);
    case 'adapters':
      await run('flutter', const <String>['analyze']);
      await run('flutter', const <String>['test']);
    case 'tooling':
      await run('dart', const <String>[
        'run',
        'dartitect_cli:dartitect',
        'contracts',
        'sync',
        'contracts/openapi.json',
        '--apply',
      ]);
      await run('dart', const <String>[
        'run',
        'dartitect_cli:dartitect',
        'contracts',
        'check',
        'contracts/openapi.json',
      ]);
      await run('dart', const <String>['analyze']);
      await run('dart', const <String>['test']);
    default:
      throw StateError('Unknown canary: $id.');
  }

  final declared = _strings(contract['commands']);
  final executed = <String>[
    for (final command in commands) command['command']! as String,
  ];
  if (!_sameStrings(declared, executed)) {
    throw StateError('$id command contract differs: $executed.');
  }
  final graph = await _validateResolvedGraph(
    workspace: workspace,
    consumer: consumer,
    repository: options.repository,
    allowedRepositories: <String>{canonicalRepository},
    ref: options.ref,
    resolvedCommit: tag.commit,
    releaseVersion: releaseVersion,
    dependencyOrder: dependencyOrder,
    requiredPackages: _strings(contract['requiredPackages']),
    forbiddenPackages: _strings(contract['forbiddenPackages']),
  );
  return <String, Object?>{
    'id': id,
    'commands': commands,
    'resolvedPackages': graph,
    'residualResourceCensus': contract['residualResourceCensus'],
    'result': 'PASS',
  };
}

/// Whether a Git canary should exercise the stable-upgrade command.
///
/// Candidate cohorts validate consumption from their disposable tag, while the
/// stable cohort also proves the idempotent upgrade path.
bool gitCanaryRunsStableUpgrade(String workspaceVersion) =>
    RegExp(r'^1\.[1-9][0-9]*\.[0-9]+$').hasMatch(workspaceVersion);

/// Redirects canonical internal Git dependencies to a disposable candidate
/// repository without changing the dependency descriptors recorded in source.
Map<String, String> gitCanaryRepositoryRedirectEnvironment({
  required String canonicalRepository,
  required String candidateRepository,
  Map<String, String> inheritedEnvironment = const <String, String>{},
}) {
  if (canonicalRepository == candidateRepository)
    return const <String, String>{};
  final rawCount = inheritedEnvironment['GIT_CONFIG_COUNT'];
  final count = rawCount == null ? 0 : int.tryParse(rawCount);
  if (count == null || count < 0) {
    throw StateError('Inherited GIT_CONFIG_COUNT is invalid.');
  }
  return <String, String>{
    'GIT_CONFIG_COUNT': '${count + 1}',
    'GIT_CONFIG_KEY_$count': 'url.$candidateRepository.insteadOf',
    'GIT_CONFIG_VALUE_$count': canonicalRepository,
  };
}

String _renderGitDependencies(
  String source, {
  required String repository,
  required String version,
}) {
  final ending = source.contains('\r\n') ? '\r\n' : '\n';
  final output = <String>[];
  String? section;
  for (final line in source.split(RegExp(r'\r?\n'))) {
    final top = RegExp(r'^([a-zA-Z_][a-zA-Z0-9_]*):(?:\s|$)').firstMatch(line);
    if (top != null) {
      section =
          const <String>{
            'dependencies',
            'dev_dependencies',
          }.contains(top.group(1))
          ? top.group(1)
          : null;
      output.add(line);
      continue;
    }
    final dependency = section == null
        ? null
        : RegExp(r'^  (dartitect(?:_[a-z0-9_]+)?):\s*[^#\s]+\s*(#.*)?$')
              .firstMatch(line);
    if (dependency == null) {
      output.add(line);
      continue;
    }
    final package = dependency.group(1)!;
    output.addAll(<String>[
      '  $package:${dependency.group(2) == null ? '' : ' ${dependency.group(2)}'}',
      '    git:',
      '      url: $repository',
      '      path: packages/$package',
      "      tag_pattern: 'v{{version}}'",
      '    version: $version',
    ]);
  }
  return output.join(ending);
}

void _assertConsumerOwnedSeams(Directory project) {
  const forbidden = <String>[
    'BootstrapCoordinator',
    'transaction.own',
    'DioOwner',
    'DriftDatabaseOwner',
    'ObjectBoxStoreOwner',
    'ObjectBoxObservationOwner',
    'SyncEngine',
    'MutationCommand',
    'JobDispatcher',
    'DartitectDiagnosticsEmitter',
  ];
  final lib = Directory('${project.path}/lib');
  for (final file
      in lib
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where(
            (file) =>
                file.path.endsWith('.dart') &&
                !file.path.endsWith('.dartitect.g.dart'),
          )) {
    final source = file.readAsStringSync();
    for (final symbol in forbidden) {
      if (source.contains(symbol)) {
        throw StateError(
          'Consumer-owned ${file.path} contains generated wiring symbol '
          '$symbol.',
        );
      }
    }
  }
  final main = File('${project.path}/lib/main.dart');
  final nonEmpty = main
      .readAsLinesSync()
      .where((line) => line.trim().isNotEmpty)
      .length;
  if (nonEmpty > 15 ||
      !main.readAsStringSync().contains('runDartitectApplication')) {
    throw StateError('Thin consumer main violates the paved-road budget.');
  }
}

String _hostDesktopTarget() {
  if (Platform.isLinux) return 'linux';
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'macos';
  throw UnsupportedError('Git desktop canary requires a desktop host.');
}

Future<List<Map<String, Object?>>> _validateResolvedGraph({
  required Directory workspace,
  required Directory consumer,
  required String repository,
  required Set<String> allowedRepositories,
  required String ref,
  required String resolvedCommit,
  required String releaseVersion,
  required List<String> dependencyOrder,
  required List<String> requiredPackages,
  required List<String> forbiddenPackages,
}) async {
  final lock = File('${consumer.path}/pubspec.lock').readAsStringSync();
  final configFile = File('${consumer.path}/.dart_tool/package_config.json');
  final config = _object(jsonDecode(configFile.readAsStringSync()));
  final entries = _objects(config['packages']);
  final names = <String>{for (final entry in entries) entry['name']! as String};
  for (final package in requiredPackages) {
    if (!names.contains(package)) {
      throw StateError('$package is absent from the $consumer graph.');
    }
  }
  for (final package in forbiddenPackages) {
    if (names.contains(package)) {
      throw StateError('$package leaked into the $consumer graph.');
    }
  }

  final graph = <Map<String, Object?>>[];
  for (final package in dependencyOrder.where(names.contains)) {
    final entry = entries.singleWhere((value) => value['name'] == package);
    final rootUri = configFile.uri.resolve(entry['rootUri']! as String);
    if (rootUri.toFilePath().startsWith(workspace.path)) {
      throw StateError('$package resolved from the local workspace.');
    }
    final locked = _lockEntry(lock, package);
    if (locked['source'] != 'git' ||
        locked['version'] != releaseVersion ||
        !allowedRepositories.contains(locked['url']) ||
        locked['tag-pattern'] != 'v{{version}}' ||
        locked['resolved-ref'] != resolvedCommit ||
        locked['path'] != 'packages/$package') {
      throw StateError('$package did not resolve from $repository@$ref.');
    }
    graph.add(<String, Object?>{
      'package': package,
      'version': releaseVersion,
      'source': 'git',
      'path': 'packages/$package',
      'resolvedCommit': resolvedCommit,
    });
  }
  return graph;
}

Future<_Tag> _resolveAnnotatedTag(Directory workspace, _Options options) async {
  final result = await _run(workspace, 'git', <String>[
    'ls-remote',
    '--tags',
    options.repository,
    'refs/tags/${options.ref}',
    'refs/tags/${options.ref}^{}',
  ]);
  String? object;
  String? commit;
  for (final line in const LineSplitter().convert(result.stdout)) {
    final fields = line.split(RegExp(r'\s+'));
    if (fields.length != 2) continue;
    if (fields[1] == 'refs/tags/${options.ref}') object = fields[0];
    if (fields[1] == 'refs/tags/${options.ref}^{}') commit = fields[0];
  }
  if (!_sha(object) || !_sha(commit) || object == commit) {
    throw StateError('${options.ref} is absent or is not an annotated tag.');
  }
  return _Tag(object!, commit!);
}

Future<void> _copyConsumer(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relative = entity.path.substring(source.path.length + 1);
    final segments = relative.split(Platform.pathSeparator);
    if (segments.any(
      (segment) =>
          segment == '.dart_tool' ||
          segment == 'build' ||
          segment == '.gradle' ||
          segment == '.kotlin' ||
          segment == 'ephemeral',
    )) {
      continue;
    }
    if (relative == 'pubspec.yaml' ||
        relative == 'pubspec.lock' ||
        relative == 'pubspec_overrides.yaml' ||
        relative == '.flutter-plugins-dependencies') {
      continue;
    }
    final target = '${destination.path}/$relative';
    if (entity is Directory) {
      await Directory(target).create(recursive: true);
    } else if (entity is File) {
      await File(target).parent.create(recursive: true);
      await entity.copy(target);
    }
  }
}

Map<String, String> _lockEntry(String source, String package) {
  final start = RegExp(
    '^  ${RegExp.escape(package)}:\\s*\$',
    multiLine: true,
  ).firstMatch(source);
  if (start == null) throw StateError('$package is absent from pubspec.lock.');
  final next = RegExp(
    r'^  [a-zA-Z0-9_]+:\s*$',
    multiLine: true,
  ).allMatches(source, start.end).firstOrNull;
  final block = source.substring(start.end, next?.start ?? source.length);
  String value(String key) =>
      RegExp(
        '^\\s+$key:\\s+["\']?([^"\'\\s]+)["\']?\\s*\$',
        multiLine: true,
      ).firstMatch(block)?.group(1) ??
      '';
  return <String, String>{
    for (final key in const <String>[
      'source',
      'version',
      'url',
      'tag-pattern',
      'resolved-ref',
      'path',
    ])
      key: value(key),
  };
}

Map<String, String> _nativeObjectBoxEnvironment(Directory workspace) {
  final directory = '${workspace.path}/tool/objectbox_native_fixture/lib';
  final result = <String, String>{'DARTITECT_NATIVE_OBJECTBOX': '1'};
  if (Platform.isWindows) {
    result['PATH'] = _prepend(directory, 'PATH', ';');
  } else if (Platform.isMacOS) {
    result['DYLD_LIBRARY_PATH'] = _prepend(directory, 'DYLD_LIBRARY_PATH', ':');
  } else {
    result['LD_LIBRARY_PATH'] = _prepend(directory, 'LD_LIBRARY_PATH', ':');
  }
  return result;
}

String _prepend(String value, String key, String separator) {
  final inherited = Platform.environment[key];
  return inherited == null || inherited.isEmpty
      ? value
      : '$value$separator$inherited';
}

Future<_Result> _run(
  Directory directory,
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  Duration timeout = const Duration(minutes: 3),
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: directory.path,
    environment: environment,
    runInShell: Platform.isWindows && executable == 'flutter',
  );
  final output = utf8.decoder.bind(process.stdout).join();
  final errors = utf8.decoder.bind(process.stderr).join();
  final code = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      process.kill();
      throw TimeoutException('$executable ${arguments.join(' ')} timed out.');
    },
  );
  final stdoutText = await output;
  final stderrText = await errors;
  if (code != 0) {
    throw StateError(
      '$executable ${arguments.join(' ')} failed in ${directory.path}:\n'
      '$stdoutText\n$stderrText',
    );
  }
  return _Result(code, stdoutText, stderrText);
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

List<Map<String, Object?>> _objects(Object? value) {
  if (value is! List<Object?>) {
    throw const FormatException('Expected a JSON object list.');
  }
  return <Map<String, Object?>>[for (final item in value) _object(item)];
}

List<String> _strings(Object? value) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw const FormatException('Expected a JSON string list.');
  }
  return value.cast<String>();
}

bool _sameStrings(List<String> left, List<String> right) =>
    left.length == right.length &&
    List<bool>.generate(
      left.length,
      (index) => left[index] == right[index],
    ).every((value) => value);

bool _sha(String? value) =>
    value != null && RegExp(r'^[0-9a-f]{40}$').hasMatch(value);

final class _Options {
  const _Options({
    required this.repository,
    required this.ref,
    required this.keepArtifacts,
  });

  factory _Options.parse(List<String> arguments) {
    String? repository;
    String? ref;
    var keepArtifacts = false;
    for (final argument in arguments) {
      if (argument.startsWith('--repository=')) {
        repository = argument.substring('--repository='.length);
      } else if (argument.startsWith('--ref=')) {
        ref = argument.substring('--ref='.length);
      } else if (argument == '--keep-artifacts') {
        keepArtifacts = true;
      } else {
        throw ArgumentError('Unknown option: $argument');
      }
    }
    if (repository == null ||
        repository.trim().isEmpty ||
        repository.contains(RegExp(r'[\r\n]')) ||
        ref == null ||
        ref.trim().isEmpty ||
        ref.contains(RegExp(r'[\r\n]'))) {
      throw ArgumentError(
        'Usage: dart run tool/run_git_canaries.dart '
        '--repository=<url> [--ref=<annotated-tag>] [--keep-artifacts]',
      );
    }
    return _Options(
      repository: repository,
      ref: ref,
      keepArtifacts: keepArtifacts,
    );
  }

  final String repository;
  final String ref;
  final bool keepArtifacts;
}

final class _Tag {
  const _Tag(this.object, this.commit);

  final String object;
  final String commit;
}

final class _Result {
  const _Result(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}
