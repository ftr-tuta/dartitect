import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../release/generated_release_manifest.dart';

/// Closed command allowlist accepted by [DartitectFleetCanaryService].
enum DartitectFleetCanaryCommand {
  /// Resolves a Dart project inside the temporary copy.
  dartPubGet('dart-pub-get', 'dart', <String>['pub', 'get']),

  /// Runs the Dart analyzer inside the temporary copy.
  dartAnalyze('dart-analyze', 'dart', <String>['analyze']),

  /// Runs Dart tests inside the temporary copy.
  dartTest('dart-test', 'dart', <String>['test']),

  /// Resolves a Flutter project inside the temporary copy.
  flutterPubGet('flutter-pub-get', 'flutter', <String>['pub', 'get']),

  /// Runs the Flutter analyzer inside the temporary copy.
  flutterAnalyze('flutter-analyze', 'flutter', <String>['analyze']),

  /// Runs Flutter tests inside the temporary copy.
  flutterTest('flutter-test', 'flutter', <String>['test']);

  const DartitectFleetCanaryCommand(this.wireName, this.executable, this.args);

  /// Stable receipt name.
  final String wireName;

  /// Exact executable selected by the allowlist.
  final String executable;

  /// Exact arguments selected by the allowlist.
  final List<String> args;
}

/// One sanitized allowlisted command receipt.
final class DartitectFleetCanaryCommandReceipt {
  /// Creates an immutable command receipt.
  const DartitectFleetCanaryCommandReceipt({
    required this.command,
    required this.exitCode,
    required this.elapsedMilliseconds,
    required this.logSha256,
    required this.sanitizedLogTail,
  });

  /// Closed command name.
  final String command;

  /// Process exit code.
  final int exitCode;

  /// Bounded wall-clock duration.
  final int elapsedMilliseconds;

  /// Digest of the complete sanitized log.
  final String logSha256;

  /// At most 16 KiB of sanitized terminal output.
  final String sanitizedLogTail;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'command': command,
    'exitCode': exitCode,
    'elapsedMilliseconds': elapsedMilliseconds,
    'logSha256': logSha256,
    'sanitizedLogTail': sanitizedLogTail,
  };
}

/// Evidence that an exact candidate ran only in an isolated project copy.
final class DartitectFleetCanaryReceipt {
  /// Creates a successful orchestration receipt.
  const DartitectFleetCanaryReceipt({
    required this.projectRoot,
    required this.candidateCommit,
    required this.archiveSha256,
    required this.commands,
    required this.exitCode,
    required this.candidateRepositoryUnchanged,
    required this.projectUnchanged,
    required this.temporaryCopyRemoved,
  });

  /// Fleet-relative source project label.
  final String projectRoot;

  /// Exact full Git commit archived for the candidate.
  final String candidateCommit;

  /// Digest of the exact candidate archive.
  final String archiveSha256;

  /// Allowlisted command receipts in execution order.
  final List<DartitectFleetCanaryCommandReceipt> commands;

  /// Zero only when every allowlisted command passed.
  final int exitCode;

  /// Whether candidate HEAD and worktree status were preserved.
  final bool candidateRepositoryUnchanged;

  /// Whether the original consumer project tree was preserved.
  final bool projectUnchanged;

  /// Whether the isolated copy was removed before returning.
  final bool temporaryCopyRemoved;

  /// Stable JSON representation without absolute paths.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'projectRoot': projectRoot,
    'candidateCommit': candidateCommit,
    'archiveSha256': archiveSha256,
    'commands': commands.map((command) => command.toJson()).toList(),
    'exitCode': exitCode,
    'candidateRepositoryUnchanged': candidateRepositoryUnchanged,
    'projectUnchanged': projectUnchanged,
    'temporaryCopyRemoved': temporaryCopyRemoved,
  };
}

/// Runs a candidate archive against a consumer only in disposable copies.
///
/// The existing read-only fleet service deliberately does not depend on this
/// class. This boundary is the only fleet API that executes processes.
final class DartitectFleetCanaryService {
  /// Creates an isolated runner from explicit candidate and fleet roots.
  DartitectFleetCanaryService({
    required Directory candidateRepository,
    required Directory fleetRoot,
  }) : candidateRepository = candidateRepository.absolute,
       fleetRoot = fleetRoot.absolute;

  /// Git repository containing the exact candidate commit.
  final Directory candidateRepository;

  /// Boundary containing consumer projects.
  final Directory fleetRoot;

  static const _repository = 'https://github.com/ftr-tuta/dartitect.git';

  /// Archives [candidateCommit], copies [projectRoot], and runs [commands].
  Future<DartitectFleetCanaryReceipt> run({
    required String projectRoot,
    required String candidateCommit,
    required Iterable<DartitectFleetCanaryCommand> commands,
  }) async {
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(candidateCommit)) {
      throw const FormatException(
        'Fleet canaries require an exact lowercase 40-character commit SHA.',
      );
    }
    final selected = commands.toList(growable: false);
    if (selected.isEmpty || selected.length > 8) {
      throw const FormatException('Fleet canaries require 1 to 8 commands.');
    }
    final label = _normalizeRelative(projectRoot);
    final candidateBoundary = await candidateRepository.resolveSymbolicLinks();
    final fleetBoundary = await fleetRoot.resolveSymbolicLinks();
    final project = Directory(_join(fleetRoot.path, label));
    final projectResolved = await project.resolveSymbolicLinks();
    _requireContained(fleetBoundary, projectResolved);
    if (!await File(_join(projectResolved, 'pubspec.yaml')).exists()) {
      throw const FormatException('Canary project has no pubspec.yaml.');
    }
    if (!await Directory(_join(candidateBoundary, '.git')).exists()) {
      throw const FormatException('Candidate root is not a Git repository.');
    }

    final candidateHeadBefore = await _gitOutput(<String>[
      'rev-parse',
      'HEAD',
    ], candidateBoundary);
    final candidateStatusBefore = await _gitOutput(<String>[
      'status',
      '--porcelain=v1',
      '--untracked-files=all',
    ], candidateBoundary);
    final resolvedCommit = await _gitOutput(<String>[
      'rev-parse',
      '--verify',
      '$candidateCommit^{commit}',
    ], candidateBoundary);
    if (resolvedCommit.trim() != candidateCommit) {
      throw const FormatException('Candidate commit did not resolve exactly.');
    }
    final projectDigestBefore = await _treeDigest(Directory(projectResolved));
    final temporary = await Directory.systemTemp.createTemp(
      'dartitect-fleet-canary-',
    );
    final receipts = <DartitectFleetCanaryCommandReceipt>[];
    var aggregateExitCode = 0;
    String? archiveDigest;
    Object? orchestrationError;
    StackTrace? orchestrationStack;
    var removed = false;
    try {
      final archive = File(_join(temporary.path, 'candidate.tar'));
      await _runRequired('git', <String>[
        'archive',
        '--format=tar',
        '--prefix=candidate/',
        '--output=${archive.path}',
        candidateCommit,
      ], candidateBoundary);
      archiveDigest = sha256.convert(await archive.readAsBytes()).toString();
      final remote = Directory(_join(temporary.path, 'dartitect.git'));
      await _runRequired('git', <String>[
        'clone',
        '--bare',
        candidateBoundary,
        remote.path,
      ], temporary.path);
      await _runRequired('git', <String>[
        '-c',
        'user.name=ftr',
        '-c',
        'user.email=ftr@tuta.com',
        '--git-dir=${remote.path}',
        'tag',
        '--annotate',
        '--force',
        DartitectReleaseManifest.consumptionTag,
        candidateCommit,
        '--message=Dartitect fleet Git canary',
      ], temporary.path);
      final taggedCommit = await _runRequired('git', <String>[
        '--git-dir=${remote.path}',
        'rev-parse',
        'refs/tags/${DartitectReleaseManifest.consumptionTag}^{}',
      ], temporary.path);
      if ('${taggedCommit.stdout}'.trim() != candidateCommit) {
        throw StateError('Fleet canary tag did not peel to the candidate.');
      }
      final copy = Directory(_join(temporary.path, 'project'));
      await copy.create();
      await _copyProject(Directory(projectResolved), copy);
      await _injectCandidate(project: copy, commit: candidateCommit);
      final gitEnvironment = <String, String>{
        ...Platform.environment,
        'GIT_CONFIG_COUNT': '1',
        'GIT_CONFIG_KEY_0': 'url.${remote.uri}.insteadOf',
        'GIT_CONFIG_VALUE_0': _repository,
      };
      for (final command in selected) {
        final stopwatch = Stopwatch()..start();
        final result = await Process.run(
          command.executable,
          command.args,
          workingDirectory: copy.path,
          runInShell: false,
          environment: gitEnvironment,
        );
        stopwatch.stop();
        final combined = '${result.stdout}\n${result.stderr}';
        final sanitized = _sanitize(combined, <String>[
          temporary.path,
          candidateBoundary,
          projectResolved,
          fleetBoundary,
        ]);
        receipts.add(
          DartitectFleetCanaryCommandReceipt(
            command: command.wireName,
            exitCode: result.exitCode,
            elapsedMilliseconds: stopwatch.elapsedMilliseconds,
            logSha256: sha256.convert(utf8.encode(sanitized)).toString(),
            sanitizedLogTail: _tail(sanitized, 16 * 1024),
          ),
        );
        if (result.exitCode != 0) {
          aggregateExitCode = 1;
          break;
        }
      }
    } catch (error, stackTrace) {
      orchestrationError = error;
      orchestrationStack = stackTrace;
    } finally {
      if (await temporary.exists()) await temporary.delete(recursive: true);
      removed = !await temporary.exists();
    }

    final candidateHeadAfter = await _gitOutput(<String>[
      'rev-parse',
      'HEAD',
    ], candidateBoundary);
    final candidateStatusAfter = await _gitOutput(<String>[
      'status',
      '--porcelain=v1',
      '--untracked-files=all',
    ], candidateBoundary);
    final projectDigestAfter = await _treeDigest(Directory(projectResolved));
    final candidateUnchanged =
        candidateHeadBefore == candidateHeadAfter &&
        candidateStatusBefore == candidateStatusAfter;
    final projectUnchanged = projectDigestBefore == projectDigestAfter;
    if (!candidateUnchanged || !projectUnchanged || !removed) {
      throw StateError(
        'Fleet canary isolation invariant failed: '
        'candidateUnchanged=$candidateUnchanged, '
        'projectUnchanged=$projectUnchanged, removed=$removed.',
      );
    }
    if (orchestrationError != null) {
      Error.throwWithStackTrace(orchestrationError, orchestrationStack!);
    }
    return DartitectFleetCanaryReceipt(
      projectRoot: label,
      candidateCommit: candidateCommit,
      archiveSha256: archiveDigest!,
      commands: List<DartitectFleetCanaryCommandReceipt>.unmodifiable(receipts),
      exitCode: aggregateExitCode,
      candidateRepositoryUnchanged: true,
      projectUnchanged: true,
      temporaryCopyRemoved: true,
    );
  }

  static Future<void> _injectCandidate({
    required Directory project,
    required String commit,
  }) async {
    final pubspecFile = File(_join(project.path, 'pubspec.yaml'));
    final pubspec = await pubspecFile.readAsString();
    final packages = _declaredDartitectPackages(pubspec);
    if (packages.isEmpty) {
      throw const FormatException(
        'Canary project declares no Dartitect package dependency.',
      );
    }
    final lineEnding = pubspec.contains('\r\n') ? '\r\n' : '\n';
    final rendered = <String>[];
    for (final line in pubspec.split(RegExp(r'\r?\n'))) {
      final match = RegExp(
        r'^  (dartitect(?:_[a-z0-9_]+)?):\s*[^#\s]+\s*(#.*)?$',
      ).firstMatch(line);
      if (match == null) {
        rendered.add(line);
        continue;
      }
      final package = match.group(1)!;
      rendered.addAll(<String>[
        '  $package:${match.group(2) == null ? '' : ' ${match.group(2)}'}',
        '    git:',
        '      url: $_repository',
        '      path: packages/$package',
        "      tag_pattern: 'v{{version}}'",
        '    version: ${DartitectReleaseManifest.consumptionVersion}',
      ]);
    }
    await pubspecFile.writeAsString(rendered.join(lineEnding), flush: true);
    final overrides = File(_join(project.path, 'pubspec_overrides.yaml'));
    if (await overrides.exists()) await overrides.delete();
    final metadata = Directory(_join(project.path, '.dartitect'));
    await metadata.create(recursive: true);
    await File(_join(metadata.path, 'candidate.json')).writeAsString(
      '${jsonEncode(<String, Object?>{'schemaVersion': 1, 'candidateCommit': commit})}\n',
    );
  }

  static Set<String> _declaredDartitectPackages(String source) {
    final result = <String>{};
    for (final match in RegExp(
      r'^  (dartitect(?:_[a-z0-9_]+)?):',
      multiLine: true,
    ).allMatches(source)) {
      result.add(match.group(1)!);
    }
    return result;
  }

  static Future<void> _copyProject(Directory source, Directory target) async {
    await for (final entity in source.list(followLinks: false)) {
      final name = entity.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .last;
      if (const <String>{
        '.git',
        '.dart_tool',
        'build',
        'coverage',
      }.contains(name)) {
        continue;
      }
      final destination = _join(target.path, name);
      if (entity is Link) {
        throw const FormatException('Canary projects cannot contain symlinks.');
      }
      if (entity is Directory) {
        final child = Directory(destination);
        await child.create();
        await _copyProject(entity, child);
      } else if (entity is File) {
        await entity.copy(destination);
      }
    }
  }

  static Future<String> _treeDigest(Directory root) async {
    final entries = <String>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      final relative = entity.path.substring(root.path.length + 1);
      if (entity is File) {
        entries.add('$relative:${sha256.convert(await entity.readAsBytes())}');
      } else if (entity is Link) {
        entries.add('$relative:link:${await entity.target()}');
      }
    }
    entries.sort();
    return sha256.convert(utf8.encode(entries.join('\n'))).toString();
  }

  static Future<String> _gitOutput(List<String> args, String root) async {
    final result = await Process.run(
      'git',
      args,
      workingDirectory: root,
      runInShell: false,
    );
    if (result.exitCode != 0) {
      throw FormatException('Git inspection failed: ${args.first}.');
    }
    return '${result.stdout}'.trimRight();
  }

  static Future<ProcessResult> _runRequired(
    String executable,
    List<String> args,
    String root,
  ) async {
    final result = await Process.run(
      executable,
      args,
      workingDirectory: root,
      runInShell: false,
    );
    if (result.exitCode != 0) {
      throw FormatException('Canary preparation failed: $executable.');
    }
    return result;
  }

  static String _sanitize(String source, Iterable<String> paths) {
    var value = source;
    for (final path in paths) {
      value = value.replaceAll(path, '<path>');
    }
    value = value.replaceAll(
      RegExp(r'https?://[^\s]+', caseSensitive: false),
      '<url>',
    );
    value = value.replaceAll(
      RegExp(
        r'(authorization|token|password|secret)\s*[:=]\s*[^\s]+',
        caseSensitive: false,
      ),
      r'$1=<redacted>',
    );
    value = value.replaceAll(
      RegExp(r'bearer\s+[^\s]+', caseSensitive: false),
      'Bearer <redacted>',
    );
    return value;
  }

  static String _tail(String value, int limit) =>
      value.length <= limit ? value : value.substring(value.length - limit);

  static String _normalizeRelative(String raw) {
    final value = raw.replaceAll('\\', '/');
    if (value.isEmpty ||
        value.startsWith('/') ||
        RegExp(r'^[A-Za-z]:/').hasMatch(value) ||
        value.split('/').any((segment) => segment.isEmpty || segment == '..')) {
      throw const FormatException('Canary project root must stay relative.');
    }
    final normalized = value
        .split('/')
        .where((segment) => segment != '.')
        .join('/');
    return normalized.isEmpty ? '.' : normalized;
  }

  static void _requireContained(String boundary, String candidate) {
    if (candidate != boundary &&
        !candidate.startsWith('$boundary${Platform.pathSeparator}')) {
      throw const FormatException('Canary project escapes the fleet root.');
    }
  }

  static String _join(String left, String right) =>
      '$left${Platform.pathSeparator}'
      '${right.replaceAll('/', Platform.pathSeparator)}';
}
