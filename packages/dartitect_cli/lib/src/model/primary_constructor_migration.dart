import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:crypto/crypto.dart';
import 'package:dartitect_modeling_analyzer/dartitect_modeling_analyzer.dart';

/// Transaction boundary exposed to deterministic migration recovery tests.
enum PrimaryConstructorMigrationFaultPoint {
  /// After the source journal is durable.
  afterJournal,

  /// After an original source is moved to its backup.
  afterBackup,

  /// After a staged primary-constructor source replaces its destination.
  afterReplacement,

  /// After commit validation and before transaction cleanup.
  beforeCleanup,
}

/// Payload-free primary migration fault event.
final class PrimaryConstructorMigrationFaultEvent {
  /// Creates an event at [point] and optional source [path].
  const PrimaryConstructorMigrationFaultEvent(this.point, {this.path});

  /// Exact transaction boundary.
  final PrimaryConstructorMigrationFaultPoint point;

  /// Workspace-relative source path, when applicable.
  final String? path;
}

/// Test-owned fault callback.
typedef PrimaryConstructorMigrationFaultInjector = FutureOr<void> Function(
  PrimaryConstructorMigrationFaultEvent event,
);

/// One semantic source replacement for an eligible value model library.
final class PrimaryConstructorMigrationOperation {
  const PrimaryConstructorMigrationOperation._({
    required this.path,
    required this.modelCount,
    required String before,
    required String after,
  }) : _before = before,
       _after = after;

  /// Workspace-relative source path.
  final String path;

  /// Number of traditional model constructors migrated in this library.
  final int modelCount;

  final String _before;
  final String _after;

  /// Payload-free machine representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'models': modelCount,
    'operation': 'migrate_primary_constructor',
  };
}

/// Stable primary-constructor migration diagnostic.
final class PrimaryConstructorMigrationDiagnostic {
  /// Creates an actionable payload-free diagnostic.
  const PrimaryConstructorMigrationDiagnostic({
    required this.rule,
    required this.message,
    required this.path,
    this.line,
    this.fixId,
  });

  /// Stable modeling rule.
  final String rule;

  /// Actionable message without source payloads.
  final String message;

  /// Workspace-relative path.
  final String path;

  /// Optional one-based line.
  final int? line;

  /// Stable semantic fix identifier when automatic migration is safe.
  final String? fixId;

  /// Stable machine representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'rule': rule,
    'severity': 'error',
    'message': message,
    'path': path,
    if (line != null) 'line': line,
    if (fixId != null) 'fixId': fixId,
  };
}

/// Complete read-only migration preview.
final class PrimaryConstructorMigrationReport {
  /// Creates a deterministic preview.
  const PrimaryConstructorMigrationReport({
    required this.operations,
    required this.diagnostics,
    required this.pendingRecovery,
    this.applied = false,
  });

  /// Eligible source replacements sorted by path.
  final List<PrimaryConstructorMigrationOperation> operations;

  /// Models that require consumer review rather than automatic edits.
  final List<PrimaryConstructorMigrationDiagnostic> diagnostics;

  /// Whether a prior source journal requires apply recovery.
  final bool pendingRecovery;

  /// Whether this invocation committed all operations.
  final bool applied;

  /// Number of model declarations covered by the preview.
  int get modelCount => operations.fold<int>(
    0,
    (total, operation) => total + operation.modelCount,
  );

  /// Stable machine representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'command': 'model migrate primary',
    'applied': applied,
    'pendingRecovery': pendingRecovery,
    'modelCount': modelCount,
    'operations': <Object?>[
      for (final operation in operations) operation.toJson(),
    ],
    'diagnostics': <Object?>[
      for (final diagnostic in diagnostics) diagnostic.toJson(),
    ],
  };
}

/// A migration could not safely converge or recover source bytes.
final class PrimaryConstructorMigrationException implements Exception {
  /// Creates a sanitized migration failure.
  const PrimaryConstructorMigrationException(this.message);

  /// Actionable payload-free message.
  final String message;

  @override
  String toString() => message;
}

/// Semantic primary-constructor codemod with its own lock and source journal.
final class PrimaryConstructorMigration {
  /// Creates a migration rooted at one project or pub workspace.
  PrimaryConstructorMigration(
    Directory root, {
    PrimaryConstructorMigrationFaultInjector? faultInjector,
  }) : root = root.absolute,
       _faultInjector = faultInjector;

  /// Workspace root.
  final Directory root;

  final PrimaryConstructorMigrationFaultInjector? _faultInjector;

  /// Discovers safe edits without modifying or recovering the workspace.
  Future<PrimaryConstructorMigrationReport> inspect() async {
    final files = await _sourceFiles();
    final operations = <PrimaryConstructorMigrationOperation>[];
    final diagnostics = <PrimaryConstructorMigrationDiagnostic>[];
    final collection = AnalysisContextCollection(
      includedPaths: <String>[root.path],
      excludedPaths: <String>[
        _join(root.path, '.dart_tool'),
        _join(root.path, 'build'),
      ],
    );
    try {
      for (final file in files) {
        final source = await file.readAsString();
        final parsed = parseString(
          content: source,
          path: file.path,
          throwIfDiagnostics: false,
        );
        final lexical = parsed.unit.declarations
            .whereType<ClassDeclaration>()
            .where(_hasLexicalDartitectValue)
            .toList(growable: false);
        if (lexical.isEmpty) continue;
        final result = await collection
            .contextFor(file.path)
            .currentSession
            .getResolvedUnit(file.path);
        if (result is! ResolvedUnitResult) {
          diagnostics.add(
            PrimaryConstructorMigrationDiagnostic(
              rule: 'DT1031',
              message: 'Analyzer could not resolve the model library.',
              path: _relative(file.path),
            ),
          );
          continue;
        }
        final edits = <ModelingSourceEdit>[];
        var modelCount = 0;
        for (final declaration
            in result.unit.declarations
                .whereType<ClassDeclaration>()
                .where(_hasLexicalDartitectValue)
                .where(_hasDartitectValue)) {
          if (declaration.namePart is PrimaryConstructorDeclaration) continue;
          final edit = primaryConstructorSourceEdits(declaration);
          if (edit == null) {
            diagnostics.add(
              PrimaryConstructorMigrationDiagnostic(
                rule: 'DT1031',
                message:
                    'Traditional constructor is not a semantics-preserving '
                    'primary-constructor migration candidate.',
                path: _relative(file.path),
                line: result.lineInfo
                    .getLocation(declaration.namePart.offset)
                    .lineNumber,
              ),
            );
            continue;
          }
          edits.addAll(edit);
          modelCount += 1;
        }
        if (edits.isEmpty) continue;
        edits.sort((left, right) => right.offset.compareTo(left.offset));
        var after = source;
        for (final edit in edits) {
          after = after.replaceRange(
            edit.offset,
            edit.offset + edit.length,
            edit.replacement,
          );
        }
        operations.add(
          PrimaryConstructorMigrationOperation._(
            path: _relative(file.path),
            modelCount: modelCount,
            before: source,
            after: after,
          ),
        );
      }
    } finally {
      await collection.dispose();
    }
    operations.sort((left, right) => left.path.compareTo(right.path));
    diagnostics.sort((left, right) {
      final byPath = left.path.compareTo(right.path);
      if (byPath != 0) return byPath;
      return (left.line ?? 0).compareTo(right.line ?? 0);
    });
    return PrimaryConstructorMigrationReport(
      operations: List<PrimaryConstructorMigrationOperation>.unmodifiable(
        operations,
      ),
      diagnostics: List<PrimaryConstructorMigrationDiagnostic>.unmodifiable(
        diagnostics,
      ),
      pendingRecovery: await _journal.exists(),
    );
  }

  /// Recovers, revalidates, and commits every eligible semantic edit.
  Future<PrimaryConstructorMigrationReport> apply() async {
    await _lock.parent.create(recursive: true);
    final lock = await _lock.open(mode: FileMode.append);
    await lock.lock(FileLock.exclusive);
    try {
      await _recover();
      final report = await inspect();
      if (report.diagnostics.isNotEmpty) {
        throw const PrimaryConstructorMigrationException(
          'Primary-constructor migration requires consumer review.',
        );
      }
      if (report.operations.isEmpty) {
        return PrimaryConstructorMigrationReport(
          operations: report.operations,
          diagnostics: report.diagnostics,
          pendingRecovery: false,
          applied: true,
        );
      }
      if (await _transaction.exists()) {
        throw const PrimaryConstructorMigrationException(
          'Primary-constructor transaction residue is not journaled.',
        );
      }
      await _transaction.create(recursive: true);
      final entries = <_MigrationJournalEntry>[];
      for (final operation in report.operations) {
        await _validatePath(operation.path);
        final staged = File(_stagePath(operation.path));
        await staged.parent.create(recursive: true);
        await staged.writeAsString(operation._after, flush: true);
        entries.add(
          _MigrationJournalEntry(
            path: operation.path,
            beforeDigest: _digest(operation._before),
            afterDigest: _digest(operation._after),
          ),
        );
      }
      var journal = _MigrationJournal(phase: 'staged', entries: entries);
      await _writeJournal(journal);
      await _fault(PrimaryConstructorMigrationFaultPoint.afterJournal);
      journal = journal.withPhase('committing');
      await _writeJournal(journal);
      try {
        for (final entry in entries) {
          final source = File(_resolve(entry.path));
          if (!await source.exists() ||
              _digest(await source.readAsString()) != entry.beforeDigest) {
            throw const PrimaryConstructorMigrationException(
              'Source changed after migration preview.',
            );
          }
          final backup = File(_backupPath(entry.path));
          await backup.parent.create(recursive: true);
          await source.rename(backup.path);
          await _fault(
            PrimaryConstructorMigrationFaultPoint.afterBackup,
            path: entry.path,
          );
          final staged = File(_stagePath(entry.path));
          await source.parent.create(recursive: true);
          await staged.rename(source.path);
          await _fault(
            PrimaryConstructorMigrationFaultPoint.afterReplacement,
            path: entry.path,
          );
        }
        await _validateAfter(entries);
        journal = journal.withPhase('committed');
        await _writeJournal(journal);
        await _fault(PrimaryConstructorMigrationFaultPoint.beforeCleanup);
        await _transaction.delete(recursive: true);
        await _journal.delete();
      } on Object {
        await _recover();
        rethrow;
      }
      return PrimaryConstructorMigrationReport(
        operations: report.operations,
        diagnostics: report.diagnostics,
        pendingRecovery: false,
        applied: true,
      );
    } finally {
      await lock.unlock();
      await lock.close();
    }
  }

  Future<void> _recover() async {
    if (!await _journal.exists()) return;
    final journal = await _readJournal();
    if (journal.phase == 'committed') {
      await _validateAfter(journal.entries);
      if (await _transaction.exists()) {
        await _transaction.delete(recursive: true);
      }
      await _journal.delete();
      return;
    }
    for (final entry in journal.entries.reversed) {
      await _validatePath(entry.path);
      final source = File(_resolve(entry.path));
      final backup = File(_backupPath(entry.path));
      if (await backup.exists()) {
        if (_digest(await backup.readAsString()) != entry.beforeDigest) {
          throw const PrimaryConstructorMigrationException(
            'Primary-constructor backup digest does not match the journal.',
          );
        }
        if (await source.exists()) {
          final current = _digest(await source.readAsString());
          if (current != entry.afterDigest && current != entry.beforeDigest) {
            throw const PrimaryConstructorMigrationException(
              'Concurrent source change prevents migration recovery.',
            );
          }
          await source.delete();
        }
        await source.parent.create(recursive: true);
        await backup.rename(source.path);
      } else if (!await source.exists() ||
          _digest(await source.readAsString()) != entry.beforeDigest) {
        throw const PrimaryConstructorMigrationException(
          'Primary-constructor recovery cannot prove original source bytes.',
        );
      }
    }
    if (await _transaction.exists()) {
      await _transaction.delete(recursive: true);
    }
    await _journal.delete();
  }

  Future<void> _validateAfter(List<_MigrationJournalEntry> entries) async {
    for (final entry in entries) {
      final source = File(_resolve(entry.path));
      if (!await source.exists() ||
          _digest(await source.readAsString()) != entry.afterDigest) {
        throw const PrimaryConstructorMigrationException(
          'Committed primary-constructor source validation failed.',
        );
      }
    }
  }

  Future<void> _fault(
    PrimaryConstructorMigrationFaultPoint point, {
    String? path,
  }) async {
    final injector = _faultInjector;
    if (injector == null) return;
    await injector(PrimaryConstructorMigrationFaultEvent(point, path: path));
  }

  Future<_MigrationJournal> _readJournal() async {
    try {
      final decoded = jsonDecode(await _journal.readAsString());
      return _MigrationJournal.fromJson(decoded);
    } on PrimaryConstructorMigrationException {
      rethrow;
    } on Object {
      throw const PrimaryConstructorMigrationException(
        'Primary-constructor migration journal is invalid.',
      );
    }
  }

  Future<void> _writeJournal(_MigrationJournal journal) async {
    await _journal.parent.create(recursive: true);
    final temporary = File('${_journal.path}.tmp');
    await temporary.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(journal.toJson())}\n',
      flush: true,
    );
    if (await _journal.exists()) await _journal.delete();
    await temporary.rename(_journal.path);
  }

  Future<List<File>> _sourceFiles() async {
    final roots = <Directory>[];
    final lib = Directory(_join(root.path, 'lib'));
    if (await lib.exists()) roots.add(lib);
    final packages = Directory(_join(root.path, 'packages'));
    if (await packages.exists()) {
      await for (final package in packages.list(followLinks: false)) {
        if (package is! Directory) continue;
        final packageLib = Directory(_join(package.path, 'lib'));
        if (await packageLib.exists()) roots.add(packageLib);
      }
    }
    final files = <File>[];
    for (final sourceRoot in roots) {
      await for (final entity in sourceRoot.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            !entity.path.endsWith('.dartitect.g.dart')) {
          files.add(entity.absolute);
        }
      }
    }
    files.sort((left, right) => left.path.compareTo(right.path));
    return files;
  }

  Future<void> _validatePath(String path) async {
    if (path.isEmpty ||
        path.startsWith('/') ||
        path.contains('\\') ||
        path.split('/').any((part) => part.isEmpty || part == '..')) {
      throw const PrimaryConstructorMigrationException(
        'Primary-constructor migration path is unsafe.',
      );
    }
    var current = root.path;
    for (final segment in path.split('/')) {
      current = _join(current, segment);
      if (await FileSystemEntity.type(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const PrimaryConstructorMigrationException(
          'Primary-constructor migration path crosses a symbolic link.',
        );
      }
    }
  }

  String _resolve(String path) => _join(root.path, path);

  String _relative(String path) => path
      .substring(root.path.length + 1)
      .replaceAll(Platform.pathSeparator, '/');

  String _stagePath(String path) => _join(_transaction.path, 'stage/$path');

  String _backupPath(String path) => _join(_transaction.path, 'backup/$path');

  File get _journal =>
      File(_resolve('.dartitect/model-primary-migration-journal.json'));

  File get _lock => File(_resolve('.dartitect/project.lock'));

  Directory get _transaction =>
      Directory(_resolve('.dartitect/model-primary-migration-transaction'));

  static String _join(String left, String right) =>
      '$left${Platform.pathSeparator}${right.replaceAll('/', Platform.pathSeparator)}';
}

bool _hasLexicalDartitectValue(ClassDeclaration declaration) =>
    declaration.metadata.any(
      (annotation) =>
          annotation.name.toSource().split('.').last == 'DartitectValue',
    );

bool _hasDartitectValue(ClassDeclaration declaration) =>
    declaration.metadata.any((annotation) {
      final element = annotation.element;
      return element?.enclosingElement?.displayName == 'DartitectValue' &&
          element?.library?.uri.toString() ==
              'package:dartitect_modeling/src/annotations.dart';
    });

String _digest(String content) =>
    sha256.convert(utf8.encode(content)).toString();

final class _MigrationJournal {
  const _MigrationJournal({required this.phase, required this.entries});

  factory _MigrationJournal.fromJson(Object? value) {
    if (value is! Map<String, Object?> ||
        value['schemaVersion'] != 1 ||
        !const <String>{
          'staged',
          'committing',
          'committed',
        }.contains(value['phase']) ||
        value['entries'] is! List<Object?>) {
      throw const FormatException('Unsupported migration journal.');
    }
    return _MigrationJournal(
      phase: value['phase']! as String,
      entries: <_MigrationJournalEntry>[
        for (final entry in value['entries']! as List<Object?>)
          _MigrationJournalEntry.fromJson(entry),
      ],
    );
  }

  final String phase;
  final List<_MigrationJournalEntry> entries;

  _MigrationJournal withPhase(String value) =>
      _MigrationJournal(phase: value, entries: entries);

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'command': 'model migrate primary',
    'phase': phase,
    'entries': <Object?>[for (final entry in entries) entry.toJson()],
  };
}

final class _MigrationJournalEntry {
  const _MigrationJournalEntry({
    required this.path,
    required this.beforeDigest,
    required this.afterDigest,
  });

  factory _MigrationJournalEntry.fromJson(Object? value) {
    if (value is! Map<String, Object?> ||
        value['path'] is! String ||
        !_digestPattern.hasMatch(value['beforeDigest'] as String? ?? '') ||
        !_digestPattern.hasMatch(value['afterDigest'] as String? ?? '')) {
      throw const FormatException('Invalid migration journal entry.');
    }
    return _MigrationJournalEntry(
      path: value['path']! as String,
      beforeDigest: value['beforeDigest']! as String,
      afterDigest: value['afterDigest']! as String,
    );
  }

  final String path;
  final String beforeDigest;
  final String afterDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'beforeDigest': beforeDigest,
    'afterDigest': afterDigest,
  };

  static final RegExp _digestPattern = RegExp(r'^[0-9a-f]{64}$');
}
