import 'dart:convert';
import 'dart:io';

import '../diagnostics/models.dart';
import 'skill_catalog.dart';

/// Outcome of synchronizing repository-owned Codex skills.
final class CodexSyncResult {
  /// Creates a result.
  const CodexSyncResult({required this.operations, required this.dryRun});

  /// Human-readable deterministic operations.
  final List<String> operations;

  /// Whether no writes were made.
  final bool dryRun;
}

/// Transactionally manages only manifest-marked `dartitect-*` skills.
final class CodexSkillSynchronizer {
  /// Creates a synchronizer rooted at a consumer workspace.
  CodexSkillSynchronizer(Directory root) : root = root.absolute;

  /// Consumer workspace.
  final Directory root;

  Directory get _skills => Directory(_join(root.path, '.agents/skills'));
  File get _journal => File(_join(root.path, '.dartitect-codex-sync.json'));
  Directory get _backup =>
      Directory(_join(root.path, '.dartitect-codex-backup'));

  /// Recovers the last interrupted commit, favoring the consumer's old data.
  Future<void> recover() async {
    if (!await _journal.exists()) return;
    final decoded = jsonDecode(await _journal.readAsString());
    final names =
        decoded is Map<String, Object?> && decoded['skills'] is List<Object?>
        ? (decoded['skills']! as List<Object?>).whereType<String>()
        : const Iterable<String>.empty();
    for (final name in names) {
      final target = Directory(_join(_skills.path, name));
      if (await target.exists()) await target.delete(recursive: true);
    }
    if (await _backup.exists()) {
      await for (final entity in _backup.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final target = Directory(_join(_skills.path, _basename(entity.path)));
        if (await target.exists()) await target.delete(recursive: true);
        await entity.rename(target.path);
      }
      await _backup.delete();
    }
    await _journal.delete();
  }

  /// Plans and optionally commits the bundled skills.
  Future<CodexSyncResult> sync({
    bool dryRun = false,
    bool overwriteManaged = false,
  }) async {
    await recover();
    final preview = await _preview(overwriteManaged: overwriteManaged);
    if (dryRun) return preview;
    final desired = _desiredFiles();

    final operations = preview.operations;
    await _skills.create(recursive: true);
    final stage = await root.createTemp('.dartitect-codex-stage-');
    try {
      for (final entry in desired.entries) {
        final directory = Directory(_join(stage.path, entry.key));
        for (final fileEntry in entry.value.entries) {
          final file = File(_join(directory.path, fileEntry.key));
          await file.parent.create(recursive: true);
          await file.writeAsString(fileEntry.value, flush: true);
        }
        final manifest = File(_join(directory.path, '.dartitect-skill.json'));
        await manifest.writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{'schemaVersion': 1, 'sdkVersion': CommandEnvelope.sdkVersion, 'contentHash': _hashFiles(entry.value)})}\n',
          flush: true,
        );
      }
      await _journal.writeAsString(
        '${jsonEncode(<String, Object?>{'schemaVersion': 1, 'phase': 'staged', 'skills': desired.keys.toList()..sort()})}\n',
        flush: true,
      );
      await _backup.create();
      for (final name in desired.keys) {
        final target = Directory(_join(_skills.path, name));
        if (await target.exists()) {
          await target.rename(_join(_backup.path, name));
        }
        await Directory(_join(stage.path, name)).rename(target.path);
      }
      final agents = File(_join(root.path, 'AGENTS.md'));
      if (!await agents.exists()) {
        await agents.writeAsString(
          '# Dartitect workspace\n\nUse the focused skills under `.agents/skills` and preserve explicit ownership boundaries.\n',
          flush: true,
        );
      }
      await _backup.delete(recursive: true);
      await _journal.delete();
    } on Object {
      await recover();
      rethrow;
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
    return CodexSyncResult(operations: operations, dryRun: false);
  }

  /// Plans synchronization without recovering or writing transaction files.
  Future<CodexSyncResult> preview({bool overwriteManaged = false}) =>
      _preview(overwriteManaged: overwriteManaged);

  Future<CodexSyncResult> _preview({required bool overwriteManaged}) async {
    if (await _journal.exists() || await _backup.exists()) {
      throw FileSystemException(
        'An interrupted Codex sync must be recovered before preview',
        _relative(_journal.path),
      );
    }
    final desired = _desiredFiles();

    final operations = <String>[];
    for (final entry in desired.entries) {
      final target = Directory(_join(_skills.path, entry.key));
      if (!await target.exists()) {
        operations.add('CREATE .agents/skills/${entry.key}');
        continue;
      }
      final manifest = File(_join(target.path, '.dartitect-skill.json'));
      if (!await manifest.exists()) {
        throw FileSystemException(
          'Refusing to replace an unmanaged skill',
          _relative(target.path),
        );
      }
      final decoded = jsonDecode(await manifest.readAsString());
      if (decoded is! Map<String, Object?> || decoded['schemaVersion'] != 1) {
        throw FileSystemException(
          'Invalid managed-skill manifest',
          _relative(manifest.path),
        );
      }
      final recordedHash = decoded['contentHash'];
      final currentHash = await _hashDirectory(target);
      if (recordedHash != currentHash && !overwriteManaged) {
        throw FileSystemException(
          'Managed skill has local changes; use --overwrite-managed to replace it',
          _relative(target.path),
        );
      }
      final desiredHash = _hashFiles(entry.value);
      operations.add(
        desiredHash == currentHash
            ? 'NO-OP .agents/skills/${entry.key}'
            : 'UPDATE .agents/skills/${entry.key}',
      );
    }
    final agents = File(_join(root.path, 'AGENTS.md'));
    if (!await agents.exists()) operations.add('CREATE AGENTS.md');
    return CodexSyncResult(operations: operations, dryRun: true);
  }

  Map<String, Map<String, String>> _desiredFiles() =>
      buildDartitectManagedSkillFiles();

  Future<String> _hashDirectory(Directory directory) async {
    final files = <String, String>{};
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File && _basename(entity.path) != '.dartitect-skill.json') {
        files[_relativeTo(directory, entity.path)] = await entity
            .readAsString();
      }
    }
    return _hashFiles(files);
  }

  static String _hashFiles(Map<String, String> files) {
    final keys = files.keys.toList()..sort();
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(
      keys.map((key) => '$key\u0000${files[key]}').join('\u0000'),
    )) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  String _relative(String path) => path
      .substring(root.path.length + 1)
      .replaceAll(Platform.pathSeparator, '/');

  static String _relativeTo(Directory directory, String path) => path
      .substring(directory.path.length + 1)
      .replaceAll(Platform.pathSeparator, '/');

  static String _basename(String path) =>
      path.split(Platform.pathSeparator).where((part) => part.isNotEmpty).last;

  static String _join(String left, String right) =>
      '$left${Platform.pathSeparator}${right.replaceAll('/', Platform.pathSeparator)}';
}
