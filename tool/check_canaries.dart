import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main(List<String> arguments) async {
  final workspace = File.fromUri(Platform.script).parent.parent.absolute;
  final allowDirty = arguments.contains('--allow-dirty');
  final keepArtifacts = arguments.contains('--keep-artifacts');
  if (arguments.any(
    (argument) => argument != '--allow-dirty' && argument != '--keep-artifacts',
  )) {
    throw ArgumentError(
      'Usage: dart run tool/check_canaries.dart [--allow-dirty] '
      '[--keep-artifacts]',
    );
  }
  final status = await _run(workspace, 'git', const <String>[
    'status',
    '--porcelain=v1',
    '--untracked-files=all',
  ]);
  final treeClean = status.stdout.trim().isEmpty;
  if (!treeClean && !allowDirty) {
    throw StateError(
      'Packaged canaries require a clean exact HEAD. Commit the intended '
      'candidate or use --allow-dirty only while developing the gate.',
    );
  }

  final contract = _jsonObject(
    await File('${workspace.path}/tool/canaries/canary_contract.json')
        .readAsString(),
  );
  final release = _jsonObject(
    await File('${workspace.path}/tool/package_release_contract.json')
        .readAsString(),
  );
  _validateContract(contract, release);

  final sourceSha = (await _run(workspace, 'git', const <String>[
    'rev-parse',
    'HEAD',
  ])).stdout.trim();
  final root = await Directory.systemTemp.createTemp(
    'dartitect-packaged-canaries-',
  );
  final receiptDirectory = Directory('${workspace.path}/build/canary-receipts');
  final receiptFile = File('${receiptDirectory.path}/v1s10-$sourceSha.json');
  var succeeded = false;
  final repository = _HostedRepository(
    workspace: workspace,
    root: Directory('${root.path}/repository'),
    sourceSha: sourceSha,
    packageNames: _strings(release['publicationOrder']),
    bundle: null,
    workingTree: !treeClean && allowDirty,
  );
  try {
    stdout.writeln(
      repository.workingTree
          ? 'Materializing reproducible development working-tree archives...'
          : 'Materializing exact-HEAD package archives...',
    );
    await repository.materialize();
    await repository.start();
    final flutter = await _flutterVersion(workspace);
    final cache = Directory('${root.path}/pub-cache');
    await cache.create(recursive: true);
    final canaryReceipts = <Map<String, Object?>>[];
    for (final value in _objects(contract['canaries'])) {
      canaryReceipts.add(
        await _runCanary(
          workspace: workspace,
          root: root,
          cache: cache,
          repository: repository,
          cohortVersion: release['cohortVersion'] as String,
          contract: value,
        ),
      );
    }
    await repository.assertArchivesRequested(<String>{
      for (final canary in _objects(contract['canaries']))
        ..._strings(canary['requiredPackages']),
    });
    final receipt = <String, Object?>{
      'schemaVersion': 1,
      'goal': 'V1S-10',
      'sourceSha': sourceSha,
      'trackedTreeClean': treeClean,
      'cohortVersion': release['cohortVersion'],
      'artifactSource': repository.workingTree
          ? 'working-tree-development'
          : contract['artifactSource'],
      'digestAlgorithm': 'sha256',
      'dartVersion': Platform.version,
      'flutterVersion': flutter,
      'hostPlatform': Platform.operatingSystem,
      'packages': repository.packageReceipts,
      'canaries': canaryReceipts,
      'deferredToV1S13': contract['deferredToV1S13'],
      'result': 'passed',
    };
    await receiptDirectory.create(recursive: true);
    await receiptFile.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(receipt)}\n',
      flush: true,
    );
    succeeded = true;
    stdout
      ..writeln('Packaged canaries passed for $sourceSha.')
      ..writeln('Receipt: ${receiptFile.path}');
  } finally {
    await repository.close();
    if (succeeded && !keepArtifacts) {
      await root.delete(recursive: true);
    } else {
      stderr.writeln('Canary artifacts retained at ${root.path}');
    }
  }
}

Future<Map<String, Object?>> _runCanary({
  required Directory workspace,
  required Directory root,
  required Directory cache,
  required _HostedRepository repository,
  required String cohortVersion,
  required Map<String, Object?> contract,
}) async {
  final id = contract['id'] as String;
  final source = Directory('${workspace.path}/${contract['source']}');
  final pubspec = File('${workspace.path}/${contract['pubspec']}');
  final consumer = Directory('${root.path}/consumers/$id');
  await _copyConsumer(source, consumer, pubspec: pubspec);
  stdout.writeln('\nValidating packaged canary: $id');
  final environment = <String, String>{
    ...Platform.environment,
    'CI': 'true',
    'PUB_CACHE': cache.path,
    'PUB_HOSTED_URL': repository.url,
  };
  final results = <Map<String, Object?>>[];
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
      environment: <String, String>{...environment, ...extraEnvironment},
      timeout: const Duration(minutes: 12),
    );
    stopwatch.stop();
    results.add(<String, Object?>{
      'command': command,
      'exitCode': result.exitCode,
      'durationMilliseconds': stopwatch.elapsedMilliseconds,
    });
  }

  await run('flutter', const <String>['pub', 'get']);
  switch (id) {
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
      break;
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
      break;
    case 'drift_provider':
      await run('dart', const <String>[
        'run',
        'build_runner',
        'build',
        '--delete-conflicting-outputs',
      ]);
      await run('dart', const <String>['analyze']);
      await run('dart', const <String>['test']);
      break;
    case 'native_capabilities':
      await run('flutter', const <String>['analyze']);
      await run('flutter', const <String>['test']);
      break;
    default:
      throw StateError('Unknown canary: $id');
  }
  final declaredCommands = _strings(contract['commands']);
  final executedCommands = <String>[
    for (final result in results) result['command'] as String,
  ];
  if (!_sameStrings(declaredCommands, executedCommands)) {
    throw StateError(
      '$id executed commands differ from its machine contract: '
      '$executedCommands.',
    );
  }

  final graph = await _validateResolvedGraph(
    consumer: consumer,
    repository: repository,
    cohortVersion: cohortVersion,
    requiredPackages: _strings(contract['requiredPackages']),
    forbiddenPackages: _strings(contract['forbiddenPackages']),
  );
  return <String, Object?>{
    'id': id,
    'consumerDirectoryIsolated': !consumer.path.startsWith(workspace.path),
    'packageSource': 'hosted',
    'monorepoPathResolution': false,
    'commands': results,
    'resolvedGraph': graph,
    'platforms': <String>[
      Platform.operatingSystem,
      if (id == 'native_capabilities') 'flutter-method-channel-contract',
      if (id == 'offline_first') 'objectbox-native-vm',
    ],
    'residualResourceCensus': contract['residualResourceCensus'],
    'result': 'passed',
  };
}

Future<List<Map<String, Object?>>> _validateResolvedGraph({
  required Directory consumer,
  required _HostedRepository repository,
  required String cohortVersion,
  required List<String> requiredPackages,
  required List<String> forbiddenPackages,
}) async {
  final lock = await File('${consumer.path}/pubspec.lock').readAsString();
  if (RegExp(r'^\s+source:\s+path\s*$', multiLine: true).hasMatch(lock)) {
    throw StateError('${consumer.path} resolved a path dependency.');
  }
  final configFile = File('${consumer.path}/.dart_tool/package_config.json');
  final config = _jsonObject(await configFile.readAsString());
  final entries = _objects(config['packages']);
  final names = <String>{for (final entry in entries) entry['name'] as String};
  for (final required in requiredPackages) {
    if (!names.contains(required)) {
      throw StateError('$required is absent from ${consumer.path}.');
    }
  }
  for (final forbidden in forbiddenPackages) {
    if (names.contains(forbidden)) {
      throw StateError('$forbidden leaked into ${consumer.path}.');
    }
  }

  final graph = <Map<String, Object?>>[];
  for (final entry in entries) {
    final name = entry['name'] as String;
    if (!repository.contains(name)) continue;
    final rootUri = configFile.uri.resolve(entry['rootUri'] as String);
    if (rootUri.toFilePath().startsWith(repository.workspace.path)) {
      throw StateError('$name resolved from the monorepo: $rootUri');
    }
    final locked = _lockEntry(lock, name);
    if (locked.source != 'hosted' ||
        locked.version != cohortVersion ||
        locked.url != repository.url) {
      throw StateError(
        '$name must resolve as hosted $cohortVersion; got '
        '${locked.source} ${locked.version} from ${locked.url}.',
      );
    }
    final artifact = repository.artifact(name);
    if (locked.sha256 != artifact.sha256) {
      throw StateError(
        '$name lock digest ${locked.sha256} does not match '
        '${artifact.sha256}.',
      );
    }
    graph.add(<String, Object?>{
      'package': name,
      'version': locked.version,
      'source': locked.source,
      'materializedChannel': true,
      'archiveSha256': locked.sha256,
    });
  }
  graph.sort(
    (left, right) =>
        (left['package'] as String).compareTo(right['package'] as String),
  );
  return graph;
}

Future<void> _copyConsumer(
  Directory source,
  Directory destination, {
  required File pubspec,
}) async {
  final pubspecSource = await pubspec.readAsString();
  if (RegExp(
    r'^dependency_overrides\s*:',
    multiLine: true,
  ).hasMatch(pubspecSource)) {
    throw StateError('${pubspec.path} contains dependency_overrides.');
  }
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
  await pubspec.copy('${destination.path}/pubspec.yaml');
}

Future<void> _copyPackageSource(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relative = entity.path.substring(source.path.length + 1);
    final segments = relative.split(Platform.pathSeparator);
    if (segments.any(
      (segment) =>
          segment == '.dart_tool' ||
          segment == '.git' ||
          segment == '.gradle' ||
          segment == '.kotlin' ||
          segment == '.symlinks' ||
          segment == 'build' ||
          segment == 'ephemeral' ||
          segment == 'node_modules' ||
          segment == 'Pods',
    )) {
      continue;
    }
    if (relative == 'pubspec.lock' ||
        relative == '.flutter-plugins-dependencies') {
      continue;
    }
    final target = File(
      '${destination.path}${Platform.pathSeparator}$relative',
    );
    if (entity is Directory) {
      await Directory(target.path).create(recursive: true);
    } else if (entity is File) {
      await target.parent.create(recursive: true);
      await entity.copy(target.path);
    } else if (entity is Link) {
      throw StateError(
        'Development package archives do not accept links: $relative.',
      );
    }
  }
}

void _validateContract(
  Map<String, Object?> contract,
  Map<String, Object?> release,
) {
  if (contract['schemaVersion'] != 1 || release['schemaVersion'] != 1) {
    throw StateError('Unsupported canary or release contract schema.');
  }
  if (contract['cohortVersion'] != release['cohortVersion']) {
    throw StateError('Canary and release cohorts differ.');
  }
  final installation = _object(contract['installation']);
  if (installation['monorepoPathResolution'] != false ||
      installation['dependencyOverrides'] != false ||
      installation['isolatedConsumerDirectories'] != true ||
      installation['sharedCacheRequiresDigestProof'] != true) {
    throw StateError('The isolated packaged-installation contract is invalid.');
  }
  final ids = <String>{
    for (final canary in _objects(contract['canaries'])) canary['id'] as String,
  };
  if (ids.length != 4 ||
      !ids.containsAll(const <String>{
        'minimal',
        'offline_first',
        'drift_provider',
        'native_capabilities',
      })) {
    throw StateError('All four formal canaries are required.');
  }
  const requiredCoverage = <String>{
    'flutter_simple',
    'objectbox_local_first',
    'outbox_sync',
    'desktop',
    'session_replacement',
    'noncooperative_cancellation',
    'large_assets',
    'multipackage_workspace',
    'consumer_owned_codegen',
    'drift_objectbox_bounded_contexts',
    'drift_provider_package',
    'drift_consumer_owned_schema',
    'drift_sync_ports',
  };
  final coverage = <String>{
    for (final canary in _objects(contract['canaries']))
      ..._strings(canary['coverage']),
  };
  if (!coverage.containsAll(requiredCoverage)) {
    throw StateError('The Goal 09 canary coverage matrix is incomplete.');
  }
  final releasePackages = _strings(release['publicationOrder']).toSet();
  for (final canary in _objects(contract['canaries'])) {
    final required = _strings(canary['requiredPackages']);
    final forbidden = _strings(canary['forbiddenPackages']);
    if (required.isEmpty ||
        _strings(canary['commands']).isEmpty ||
        canary['residualResourceCensus'] != 0 ||
        required.toSet().length != required.length ||
        forbidden.toSet().length != forbidden.length ||
        required.toSet().intersection(forbidden.toSet()).isNotEmpty ||
        !releasePackages.containsAll(required) ||
        !releasePackages.containsAll(forbidden)) {
      throw StateError('${canary['id']} has an incomplete execution contract.');
    }
  }
}

String _hostDesktopTarget() {
  if (Platform.isLinux) return 'linux';
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'macos';
  throw UnsupportedError('Packaged desktop canary requires a desktop host.');
}

Map<String, String> _nativeObjectBoxEnvironment(Directory workspace) {
  final libraryDirectory =
      '${workspace.path}/tool/objectbox_native_fixture/lib';
  final environment = <String, String>{'DARTITECT_NATIVE_OBJECTBOX': '1'};
  if (Platform.isWindows) {
    environment['PATH'] = _prependPath(libraryDirectory, 'PATH', ';');
  } else if (Platform.isMacOS) {
    environment['DYLD_LIBRARY_PATH'] = _prependPath(
      libraryDirectory,
      'DYLD_LIBRARY_PATH',
      ':',
    );
  } else {
    environment['LD_LIBRARY_PATH'] = _prependPath(
      libraryDirectory,
      'LD_LIBRARY_PATH',
      ':',
    );
  }
  return environment;
}

String _prependPath(String value, String key, String separator) {
  final inherited = Platform.environment[key];
  return inherited == null || inherited.isEmpty
      ? value
      : '$value$separator$inherited';
}

Future<Map<String, Object?>> _flutterVersion(Directory workspace) async {
  final result = await _run(workspace, 'flutter', const <String>[
    '--version',
    '--machine',
  ]);
  final value = jsonDecode(result.stdout);
  if (value is! Map<String, Object?>) {
    throw StateError('Flutter returned an invalid version payload.');
  }
  return <String, Object?>{
    'frameworkVersion': value['frameworkVersion'],
    'channel': value['channel'],
    'dartSdkVersion': value['dartSdkVersion'],
  };
}

Future<_ProcessResult> _run(
  Directory workingDirectory,
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  Duration timeout = const Duration(minutes: 3),
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
    environment: environment,
    runInShell: Platform.isWindows && executable == 'flutter',
  );
  final stdoutFuture = utf8.decoder.bind(process.stdout).join();
  final stderrFuture = utf8.decoder.bind(process.stderr).join();
  final exitCode = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      process.kill();
      throw TimeoutException(
        '$executable ${arguments.join(' ')} exceeded $timeout.',
      );
    },
  );
  final output = await stdoutFuture;
  final errors = await stderrFuture;
  if (exitCode != 0) {
    throw StateError(
      '$executable ${arguments.join(' ')} failed in '
      '${workingDirectory.path}:\n$output\n$errors',
    );
  }
  return _ProcessResult(exitCode, output, errors);
}

final class _HostedRepository {
  _HostedRepository({
    required this.workspace,
    required this.root,
    required this.sourceSha,
    required this.packageNames,
    this.bundle,
    this.workingTree = false,
  });

  final Directory workspace;
  final Directory root;
  final String sourceSha;
  final List<String> packageNames;
  final Directory? bundle;
  final bool workingTree;
  final Map<String, _Artifact> _artifacts = <String, _Artifact>{};
  final Map<String, int> _requests = <String, int>{};
  HttpServer? _server;
  HttpClient? _proxyClient;

  String get url {
    final server = _server;
    if (server == null) throw StateError('Hosted repository is not running.');
    return 'http://${server.address.address}:${server.port}';
  }

  List<Map<String, Object?>> get packageReceipts => <Map<String, Object?>>[
    for (final name in packageNames)
      <String, Object?>{
        'package': name,
        'version': _artifacts[name]!.version,
        'archiveSha256': _artifacts[name]!.sha256,
        'archiveFormat': 'tar.gz',
        'reproducible': true,
        'archiveRequests': _requests[name] ?? 0,
        'sourceSha': sourceSha,
        'workingTree': workingTree,
      },
  ];

  _Artifact artifact(String name) =>
      _artifacts[name] ?? (throw StateError('Unknown package $name.'));

  bool contains(String name) => _artifacts.containsKey(name);

  Future<void> materialize() async {
    await root.create(recursive: true);
    if (bundle != null) {
      await _loadBundle();
      return;
    }
    for (final name in packageNames) {
      final package = Directory('${workspace.path}/packages/$name');
      if (!package.existsSync()) throw StateError('Missing package $name.');
      final pubspecFile = File('${package.path}/pubspec.yaml');
      final pubspec = _hostedPubspec(await pubspecFile.readAsString());
      final version = pubspec['version'] as String;
      final archive = File('${root.path}/$name-$version.tar.gz');
      final tar = File('${root.path}/$name-$version.tar');
      if (workingTree) {
        await _archiveWorkingTreePackage(package, tar, name);
      } else {
        await _run(workspace, 'git', <String>[
          'archive',
          '--format=tar',
          '--output=${tar.path}',
          '$sourceSha:packages/$name',
        ]);
      }
      final tarBytes = await tar.readAsBytes();
      final firstEncoding = gzip.encode(tarBytes);
      final secondEncoding = gzip.encode(tarBytes);
      final firstDigest = sha256.convert(firstEncoding);
      final secondDigest = sha256.convert(secondEncoding);
      if (firstDigest != secondDigest) {
        throw StateError('$name archive compression is not reproducible.');
      }
      await archive.writeAsBytes(firstEncoding, flush: true);
      await tar.delete();
      final digest = sha256.convert(await archive.readAsBytes()).toString();
      _artifacts[name] = _Artifact(
        name: name,
        version: version,
        pubspec: pubspec,
        archive: archive,
        sha256: digest,
      );
    }
  }

  Future<void> _archiveWorkingTreePackage(
    Directory package,
    File tar,
    String name,
  ) async {
    final checkout = Directory('${root.path}/working-tree/$name');
    await _copyPackageSource(package, checkout);
    await _run(checkout, 'git', const <String>['init', '--quiet']);
    await _run(checkout, 'git', const <String>['add', '--all']);
    await _run(
      checkout,
      'git',
      const <String>[
        '-c',
        'user.name=Dartitect Canary',
        '-c',
        'user.email=canary@invalid.example',
        'commit',
        '--quiet',
        '--no-gpg-sign',
        '-m',
        'working-tree canary',
      ],
      environment: <String, String>{
        ...Platform.environment,
        'GIT_AUTHOR_DATE': '2000-01-01T00:00:00Z',
        'GIT_COMMITTER_DATE': '2000-01-01T00:00:00Z',
      },
    );
    await _run(checkout, 'git', <String>[
      'archive',
      '--format=tar',
      '--output=${tar.path}',
      'HEAD',
    ]);
  }

  Future<void> _loadBundle() async {
    final manifest = _jsonObject(
      await File('${bundle!.path}/bundle-manifest.json').readAsString(),
    );
    if (manifest['schemaVersion'] != 1 ||
        manifest['goal'] != 'V1S-16' ||
        manifest['state'] != 'CANDIDATE_BUNDLE' ||
        manifest['channel'] != 'signed-bundle' ||
        manifest['sourceSha'] != sourceSha ||
        manifest['packageCount'] != packageNames.length) {
      throw StateError('The materialized bundle manifest is invalid.');
    }
    final entries = <String, Map<String, Object?>>{
      for (final entry in _objects(manifest['packages']))
        entry['package']! as String: entry,
    };
    if (entries.length != packageNames.length ||
        !entries.keys.toSet().containsAll(packageNames)) {
      throw StateError('The materialized bundle package cohort is incomplete.');
    }
    for (var index = 0; index < packageNames.length; index += 1) {
      final name = packageNames[index];
      final entry = entries[name]!;
      final archivePath = entry['archive'];
      final expectedDigest = entry['archiveSha256'];
      final pubspec = _object(entry['hostedPubspec']);
      final archive = archivePath is String
          ? File('${bundle!.path}/$archivePath')
          : File('');
      if (entry['orderIndex'] != index ||
          entry['version'] != pubspec['version'] ||
          pubspec['name'] != name ||
          !archive.existsSync() ||
          expectedDigest is! String ||
          sha256.convert(await archive.readAsBytes()).toString() !=
              expectedDigest) {
        throw StateError('$name materialized archive is invalid.');
      }
      _artifacts[name] = _Artifact(
        name: name,
        version: entry['version']! as String,
        pubspec: pubspec,
        archive: archive,
        sha256: expectedDigest,
      );
    }
  }

  Future<void> start() async {
    _proxyClient = HttpClient()..autoUncompress = false;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_server!.forEach(_handle));
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _proxyClient?.close(force: true);
  }

  Future<void> assertArchivesRequested(Set<String> requiredPackages) async {
    final absent = <String>[
      for (final name in requiredPackages)
        if ((_requests[name] ?? 0) == 0) name,
    ];
    if (absent.isNotEmpty) {
      throw StateError(
        'The materialized cohort was incomplete; archives never requested: '
        '${absent.join(', ')}.',
      );
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final segments = request.uri.pathSegments;
      if (request.method == 'GET' &&
          segments.length == 3 &&
          segments[0] == 'api' &&
          segments[1] == 'packages') {
        final artifact = _artifacts[segments[2]];
        if (artifact != null) {
          await _serveMetadata(request.response, artifact);
          return;
        }
      }
      if (request.method == 'GET' &&
          segments.length == 2 &&
          segments[0] == 'packages') {
        final artifact = _artifacts.values
            .where(
              (value) => value.archive.uri.pathSegments.last == segments[1],
            )
            .firstOrNull;
        if (artifact != null) {
          _requests.update(
            artifact.name,
            (value) => value + 1,
            ifAbsent: () => 1,
          );
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType('application', 'gzip')
            ..contentLength = await artifact.archive.length();
          await request.response.addStream(artifact.archive.openRead());
          await request.response.close();
          return;
        }
      }
      await _proxy(request);
    } catch (error, stackTrace) {
      stderr.writeln('Hosted repository request failed: $error\n$stackTrace');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } on StateError {
        // The response may already be committed by a failed upstream stream.
      }
    }
  }

  Future<void> _serveMetadata(HttpResponse response, _Artifact artifact) async {
    final version = <String, Object?>{
      'version': artifact.version,
      'pubspec': artifact.pubspec,
      'archive_url': '$url/packages/${artifact.archive.uri.pathSegments.last}',
      'archive_sha256': artifact.sha256,
      'published': '1970-01-01T00:00:00.000Z',
    };
    response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode(<String, Object?>{
          'name': artifact.name,
          'latest': version,
          'versions': <Map<String, Object?>>[version],
        }),
      );
    await response.close();
  }

  Future<void> _proxy(HttpRequest request) async {
    final upstreamUri = Uri(
      scheme: 'https',
      host: 'pub.dev',
      path: request.uri.path,
      query: request.uri.hasQuery ? request.uri.query : null,
    );
    final upstreamRequest = await _proxyClient!.getUrl(upstreamUri);
    upstreamRequest.headers.set(
      HttpHeaders.userAgentHeader,
      'dartitect-packaged-canary/1.0',
    );
    final upstream = await upstreamRequest.close();
    request.response.statusCode = upstream.statusCode;
    for (final name in const <String>[
      HttpHeaders.contentTypeHeader,
      HttpHeaders.contentEncodingHeader,
      HttpHeaders.cacheControlHeader,
      HttpHeaders.etagHeader,
      HttpHeaders.locationHeader,
    ]) {
      final values = upstream.headers[name];
      if (values != null) request.response.headers.set(name, values);
    }
    if (upstream.contentLength >= 0) {
      request.response.contentLength = upstream.contentLength;
    }
    await request.response.addStream(upstream);
    await request.response.close();
  }
}

Map<String, Object?> _hostedPubspec(String source) {
  final result = <String, Object?>{};
  final sections = <String, Map<String, Object?>>{
    'environment': <String, Object?>{},
    'dependencies': <String, Object?>{},
  };
  String? section;
  String? nestedKey;
  for (final raw in const LineSplitter().convert(source)) {
    final line = raw.split(' #').first;
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    final indent = line.length - line.trimLeft().length;
    final separator = line.indexOf(':');
    if (separator < 0) continue;
    final key = line.substring(indent, separator).trim();
    final rawValue = line.substring(separator + 1).trim();
    if (indent == 0) {
      nestedKey = null;
      section = sections.containsKey(key) ? key : null;
      if (key == 'name' || key == 'version') {
        result[key] = _yamlScalar(rawValue);
      }
      continue;
    }
    if (indent == 2 && section != null) {
      nestedKey = rawValue.isEmpty ? key : null;
      sections[section]![key] = rawValue.isEmpty
          ? <String, Object?>{}
          : _yamlScalar(rawValue);
      continue;
    }
    if (indent == 4 && section != null && nestedKey != null) {
      final nested = sections[section]![nestedKey] as Map<String, Object?>;
      nested[key] = _yamlScalar(rawValue);
    }
  }
  if (result['name'] is! String || result['version'] is! String) {
    throw StateError('Package pubspec is missing name or version.');
  }
  result.addAll(sections);
  return result;
}

String _yamlScalar(String value) {
  if (value.length >= 2 &&
      ((value.startsWith("'") && value.endsWith("'")) ||
          (value.startsWith('"') && value.endsWith('"')))) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

_LockEntry _lockEntry(String source, String package) {
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
  String value(String key) {
    final match = RegExp(
      '^\\s+$key:\\s+["\']?([^"\'\\s]+)["\']?\\s*\$',
      multiLine: true,
    ).firstMatch(block);
    return match?.group(1) ?? '';
  }

  return _LockEntry(
    source: value('source'),
    version: value('version'),
    sha256: value('sha256'),
    url: value('url'),
  );
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Map<String, Object?> _jsonObject(String source) {
  final value = jsonDecode(source);
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object field.');
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

final class _Artifact {
  const _Artifact({
    required this.name,
    required this.version,
    required this.pubspec,
    required this.archive,
    required this.sha256,
  });

  final String name;
  final String version;
  final Map<String, Object?> pubspec;
  final File archive;
  final String sha256;
}

final class _LockEntry {
  const _LockEntry({
    required this.source,
    required this.version,
    required this.sha256,
    required this.url,
  });

  final String source;
  final String version;
  final String sha256;
  final String url;
}

final class _ProcessResult {
  const _ProcessResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}
