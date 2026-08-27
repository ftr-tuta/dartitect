import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Ownership class of generated content.
enum GeneratedOwnership {
  /// Created once and owned by the consumer afterward.
  generatedOnce,

  /// Entire file remains owned through a strong manifest entry.
  fullyGenerated,
}

/// One in-memory file generation operation.
final class FileGenerationOperation {
  /// Creates an operation with a project-relative POSIX-style path.
  const FileGenerationOperation({
    required this.relativePath,
    required this.content,
    this.ownership = GeneratedOwnership.generatedOnce,
    this.sourcePath,
    this.generatorVersion = '1.0.0-rc.2',
    this.inputSchemaVersion = 1,
    this.inputSignature,
  });

  /// Project-relative output path.
  final String relativePath;

  /// Fully rendered content.
  final String content;

  /// Who owns subsequent changes.
  final GeneratedOwnership ownership;

  /// Project-relative source path for fully generated output.
  final String? sourcePath;

  /// Generator version recorded in the ownership manifest.
  final String generatorVersion;

  /// Semantic input schema version.
  final int inputSchemaVersion;

  /// Canonical semantic model signature, excluding formatting/comments.
  final String? inputSignature;
}

/// Resolution of one operation against the destination tree.
enum GenerationDisposition {
  /// Target does not exist and can be created.
  create,

  /// Manifest-owned target will be replaced.
  update,

  /// Manifest-owned orphan will be removed.
  delete,

  /// Target and ownership metadata are current.
  noOp,

  /// Target or manifest ownership cannot be proven.
  conflict,
}

/// One resolved operation in a generation plan.
final class PlannedFileOperation {
  const PlannedFileOperation._(
    this.operation,
    this.disposition, {
    this.previousOutputDigest,
  });

  /// Original or synthesized render operation.
  final FileGenerationOperation operation;

  /// Destination resolution.
  final GenerationDisposition disposition;

  /// Prior canonical manifest digest when one exists.
  final String? previousOutputDigest;

  /// Deterministic human preview without reading arbitrary consumer bytes.
  String get preview => switch (disposition) {
    GenerationDisposition.create =>
      '--- /dev/null\n+++ ${operation.relativePath}\n'
          '${_canonicalText(operation.content).split('\n').map((line) => '+$line').join('\n')}',
    GenerationDisposition.update => 'update ${operation.relativePath}',
    GenerationDisposition.delete => 'delete ${operation.relativePath}',
    GenerationDisposition.noOp => 'no-op ${operation.relativePath}',
    GenerationDisposition.conflict => 'conflict ${operation.relativePath}',
  };
}

/// Immutable, fully validated generation plan.
final class GenerationPlan {
  const GenerationPlan._(
    this.operations, {
    required this.pendingRecovery,
    required this.managesFullyGenerated,
    required List<_ManifestEntry> nextManifestEntries,
  }) : _nextManifestEntries = nextManifestEntries;

  /// Operations sorted by normalized path.
  final List<PlannedFileOperation> operations;

  /// Whether a prior transaction journal requires explicit apply recovery.
  final bool pendingRecovery;

  /// Whether this plan converges the complete fully-generated set.
  final bool managesFullyGenerated;

  final List<_ManifestEntry> _nextManifestEntries;

  /// Whether any destination has unproven or diverged ownership.
  bool get hasConflicts => operations.any(
    (operation) => operation.disposition == GenerationDisposition.conflict,
  );

  /// Whether applying the plan changes an output or manifest entry.
  bool get hasChanges => operations.any(
    (operation) =>
        operation.disposition != GenerationDisposition.noOp &&
        operation.disposition != GenerationDisposition.conflict,
  );

  /// Files that would be created.
  Iterable<PlannedFileOperation> get creates => operations.where(
    (operation) => operation.disposition == GenerationDisposition.create,
  );

  /// Files that would be updated.
  Iterable<PlannedFileOperation> get updates => operations.where(
    (operation) => operation.disposition == GenerationDisposition.update,
  );

  /// Files that would be removed.
  Iterable<PlannedFileOperation> get deletes => operations.where(
    (operation) => operation.disposition == GenerationDisposition.delete,
  );
}

/// Result of a dry-run or committed generation transaction.
final class GenerationResult {
  /// Creates an immutable generation receipt.
  const GenerationResult({
    required this.plan,
    required this.dryRun,
    required this.createdPaths,
    this.updatedPaths = const <String>[],
    this.deletedPaths = const <String>[],
  });

  /// Revalidated plan used by this invocation.
  final GenerationPlan plan;

  /// Whether no filesystem mutations were attempted.
  final bool dryRun;

  /// Project-relative files created by this invocation.
  final List<String> createdPaths;

  /// Project-relative files replaced by this invocation.
  final List<String> updatedPaths;

  /// Project-relative files removed by this invocation.
  final List<String> deletedPaths;
}

/// Stable failure category used by CLI exit-code mapping.
enum GenerationFailureKind {
  /// Consumer bytes or unmanaged paths prevent convergence.
  conflict,

  /// Manifest, path, schema, or invocation configuration is invalid.
  invalidConfiguration,

  /// An interrupted transaction could not be safely restored.
  recovery,

  /// Filesystem or unexpected commit failure.
  io,
}

/// Deterministic transaction boundary available to recovery contract tests.
enum GenerationFaultPoint {
  /// Immediately before one output is staged.
  beforeStageOutput,

  /// Immediately after one output is staged and hashed.
  afterStageOutput,

  /// Immediately before the next ownership manifest is staged.
  beforeStageManifest,

  /// Immediately after the next ownership manifest is staged and hashed.
  afterStageManifest,

  /// Immediately before the recovery journal becomes durable.
  beforePersistJournal,

  /// Immediately after the staged recovery journal becomes durable.
  afterPersistJournal,

  /// Immediately before an existing destination is moved to backup.
  beforeBackup,

  /// Immediately after the backup is durable and verified.
  afterBackup,

  /// Immediately before one staged output replaces its destination.
  beforeReplacement,

  /// Immediately after one staged output replaces its destination.
  afterReplacement,

  /// Immediately before the staged manifest replaces its destination.
  beforeManifestReplacement,

  /// Immediately after the staged manifest replaces its destination.
  afterManifestReplacement,

  /// Immediately before committed transaction residue is removed.
  beforeCleanup,

  /// After transaction cleanup and before the committed journal is removed.
  afterCleanup,
}

/// One payload-free generation fault injection event.
final class GenerationFaultEvent {
  /// Creates an event for [point] and optional project-relative [path].
  const GenerationFaultEvent(this.point, {this.path});

  /// Exact transaction boundary.
  final GenerationFaultPoint point;

  /// Affected output or manifest path, when applicable.
  final String? path;
}

/// Test-owned callback that may fail one exact transaction boundary.
typedef GenerationFaultInjector = FutureOr<void> Function(
  GenerationFaultEvent event,
);

/// A generation conflict, invalid configuration, or recovery failure.
final class GenerationException implements Exception {
  /// Creates an actionable failure.
  const GenerationException(
    this.message, {
    this.kind = GenerationFailureKind.conflict,
    this.recoveryPaths = const <String>[],
  });

  /// Sanitized failure message.
  final String message;

  /// Stable failure category.
  final GenerationFailureKind kind;

  /// Relative paths that may need manual recovery.
  final List<String> recoveryPaths;

  @override
  String toString() => message;
}

/// Transactional generation engine for generated-once and fully-generated files.
final class GenerationEngine {
  /// Creates an engine rooted at an existing or creatable project directory.
  GenerationEngine(Directory root, {GenerationFaultInjector? faultInjector})
    : root = root.absolute,
      _faultInjector = faultInjector;

  /// Destination project root.
  final Directory root;

  final GenerationFaultInjector? _faultInjector;

  /// Resolves all requested operations without writing.
  ///
  /// Set [manageFullyGenerated] only when [requested] is the complete desired
  /// set for `.dartitect/model-outputs.json`; an empty set then removes orphans.
  Future<GenerationPlan> plan(
    Iterable<FileGenerationOperation> requested, {
    bool manageFullyGenerated = false,
  }) async {
    final byPath = <String, FileGenerationOperation>{};
    for (final operation in requested) {
      _validatePath(operation.relativePath);
      if (operation.relativePath.contains('\\')) {
        throw const GenerationException(
          'Output paths must use normalized forward slashes.',
          kind: GenerationFailureKind.invalidConfiguration,
        );
      }
      if (operation.ownership == GeneratedOwnership.fullyGenerated) {
        if (!manageFullyGenerated) {
          throw const GenerationException(
            'Fully-generated operations require complete-set management.',
            kind: GenerationFailureKind.invalidConfiguration,
          );
        }
        _validateFullyGenerated(operation);
      }
      final prior = byPath[operation.relativePath];
      if (prior != null &&
          (prior.content != operation.content ||
              prior.ownership != operation.ownership ||
              prior.sourcePath != operation.sourcePath)) {
        throw GenerationException(
          'Two operations diverge for ${operation.relativePath}.',
          kind: GenerationFailureKind.invalidConfiguration,
        );
      }
      byPath[operation.relativePath] = operation;
    }

    final manifest = manageFullyGenerated ? await _readManifest() : null;
    final previous = <String, _ManifestEntry>{
      for (final entry in manifest?.entries ?? const <_ManifestEntry>[])
        entry.path: entry,
    };
    final desiredFullyGenerated = <String, FileGenerationOperation>{
      for (final entry in byPath.entries)
        if (entry.value.ownership == GeneratedOwnership.fullyGenerated)
          entry.key: entry.value,
    };
    final operations = <PlannedFileOperation>[];

    if (manageFullyGenerated && manifest == null) {
      final candidates = await _findUnmanagedModelOutputs();
      for (final path in candidates) {
        if (!byPath.containsKey(path)) {
          operations.add(
            PlannedFileOperation._(
              FileGenerationOperation(
                relativePath: path,
                content: '',
                ownership: GeneratedOwnership.fullyGenerated,
                sourcePath: path,
                inputSignature: path,
              ),
              GenerationDisposition.conflict,
            ),
          );
        }
      }
    }

    for (final entry in byPath.entries) {
      final path = entry.key;
      final operation = entry.value;
      await _validateNoSymlinkPath(path);
      final destination = File(_resolve(path));
      final type = await FileSystemEntity.type(
        destination.path,
        followLinks: false,
      );
      if (operation.ownership == GeneratedOwnership.generatedOnce) {
        final disposition = switch (type) {
          FileSystemEntityType.notFound => GenerationDisposition.create,
          FileSystemEntityType.file =>
            _equivalent(await destination.readAsString(), operation.content)
                ? GenerationDisposition.noOp
                : GenerationDisposition.conflict,
          _ => GenerationDisposition.conflict,
        };
        operations.add(PlannedFileOperation._(operation, disposition));
        continue;
      }

      final prior = previous[path];
      if (prior == null) {
        operations.add(
          PlannedFileOperation._(
            operation,
            type == FileSystemEntityType.notFound
                ? GenerationDisposition.create
                : GenerationDisposition.conflict,
          ),
        );
        continue;
      }
      if (prior.source != operation.sourcePath) {
        operations.add(
          PlannedFileOperation._(
            operation,
            GenerationDisposition.conflict,
            previousOutputDigest: prior.outputDigest,
          ),
        );
        continue;
      }
      if (type == FileSystemEntityType.notFound) {
        operations.add(
          PlannedFileOperation._(
            operation,
            GenerationDisposition.create,
            previousOutputDigest: prior.outputDigest,
          ),
        );
        continue;
      }
      if (type != FileSystemEntityType.file ||
          await _canonicalFileDigest(destination) != prior.outputDigest) {
        operations.add(
          PlannedFileOperation._(
            operation,
            GenerationDisposition.conflict,
            previousOutputDigest: prior.outputDigest,
          ),
        );
        continue;
      }
      final desired = _entryFor(operation);
      final disposition = desired == prior
          ? GenerationDisposition.noOp
          : GenerationDisposition.update;
      operations.add(
        PlannedFileOperation._(
          operation,
          disposition,
          previousOutputDigest: prior.outputDigest,
        ),
      );
    }

    if (manageFullyGenerated) {
      for (final prior in previous.values) {
        if (desiredFullyGenerated.containsKey(prior.path)) continue;
        await _validateNoSymlinkPath(prior.path);
        final destination = File(_resolve(prior.path));
        final type = await FileSystemEntity.type(
          destination.path,
          followLinks: false,
        );
        final disposition = type == FileSystemEntityType.notFound
            ? GenerationDisposition.delete
            : type == FileSystemEntityType.file &&
                  await _canonicalFileDigest(destination) == prior.outputDigest
            ? GenerationDisposition.delete
            : GenerationDisposition.conflict;
        operations.add(
          PlannedFileOperation._(
            FileGenerationOperation(
              relativePath: prior.path,
              content: '',
              ownership: GeneratedOwnership.fullyGenerated,
              sourcePath: prior.source,
              generatorVersion: prior.generatorVersion,
              inputSchemaVersion: prior.inputSchemaVersion,
              inputSignature: prior.inputDigest,
            ),
            disposition,
            previousOutputDigest: prior.outputDigest,
          ),
        );
      }
    }

    operations.sort(
      (left, right) =>
          left.operation.relativePath.compareTo(right.operation.relativePath),
    );
    final nextEntries = <_ManifestEntry>[
      for (final operation in desiredFullyGenerated.values)
        _entryFor(operation),
    ]..sort((left, right) => left.path.compareTo(right.path));
    return GenerationPlan._(
      List<PlannedFileOperation>.unmodifiable(operations),
      pendingRecovery: await _journal.exists(),
      managesFullyGenerated: manageFullyGenerated,
      nextManifestEntries: List<_ManifestEntry>.unmodifiable(nextEntries),
    );
  }

  /// Recovers any prior transaction, replans, stages, and commits [requested].
  Future<GenerationResult> apply(
    Iterable<FileGenerationOperation> requested, {
    bool dryRun = false,
    bool manageFullyGenerated = false,
  }) async {
    if (dryRun) {
      final preview = await plan(
        requested,
        manageFullyGenerated: manageFullyGenerated,
      );
      return GenerationResult(
        plan: preview,
        dryRun: true,
        createdPaths: const <String>[],
      );
    }
    await recover();
    final resolved = await plan(
      requested,
      manageFullyGenerated: manageFullyGenerated,
    );
    if (resolved.hasConflicts) {
      final conflicts = resolved.operations
          .where(
            (operation) =>
                operation.disposition == GenerationDisposition.conflict,
          )
          .map((operation) => operation.operation.relativePath)
          .toList();
      throw GenerationException(
        'Generation ownership conflicts with: ${conflicts.join(', ')}.',
        recoveryPaths: conflicts,
      );
    }
    if (!resolved.hasChanges) {
      return GenerationResult(
        plan: resolved,
        dryRun: false,
        createdPaths: const <String>[],
      );
    }

    await root.create(recursive: true);
    if (await _transaction.exists()) {
      throw GenerationException(
        'Generation transaction residue exists without a recoverable journal.',
        kind: GenerationFailureKind.invalidConfiguration,
        recoveryPaths: <String>[_relative(_transaction.path)],
      );
    }
    await _transaction.create(recursive: true);
    final changed = resolved.operations
        .where(
          (operation) => operation.disposition != GenerationDisposition.noOp,
        )
        .toList(growable: false);
    final journalEntries = <_JournalEntry>[];
    try {
      for (final planned in changed) {
        final path = planned.operation.relativePath;
        final destination = File(_resolve(path));
        final beforeExists = await destination.exists();
        final beforeDigest = beforeExists
            ? await _rawDigest(destination)
            : null;
        final afterExists = planned.disposition != GenerationDisposition.delete;
        String? afterDigest;
        if (afterExists) {
          final staged = File(_stagePath(path));
          await _fault(GenerationFaultPoint.beforeStageOutput, path: path);
          await staged.parent.create(recursive: true);
          final content =
              planned.operation.ownership == GeneratedOwnership.fullyGenerated
              ? _canonicalText(planned.operation.content)
              : planned.operation.content;
          await staged.writeAsString(content, flush: true);
          afterDigest = await _rawDigest(staged);
          await _fault(GenerationFaultPoint.afterStageOutput, path: path);
        }
        journalEntries.add(
          _JournalEntry(
            path: path,
            disposition: planned.disposition,
            beforeExists: beforeExists,
            beforeDigest: beforeDigest,
            afterExists: afterExists,
            afterDigest: afterDigest,
          ),
        );
      }

      _JournalEntry? manifestJournal;
      if (resolved.managesFullyGenerated) {
        await _validateNoSymlinkPath(_manifestRelativePath);
        final stagedManifest = File(_stageManifestPath);
        await _fault(
          GenerationFaultPoint.beforeStageManifest,
          path: _manifestRelativePath,
        );
        await stagedManifest.parent.create(recursive: true);
        await stagedManifest.writeAsString(
          _encodeManifest(resolved._nextManifestEntries),
          flush: true,
        );
        final beforeExists = await _manifest.exists();
        manifestJournal = _JournalEntry(
          path: _manifestRelativePath,
          disposition: beforeExists
              ? GenerationDisposition.update
              : GenerationDisposition.create,
          beforeExists: beforeExists,
          beforeDigest: beforeExists ? await _rawDigest(_manifest) : null,
          afterExists: true,
          afterDigest: await _rawDigest(stagedManifest),
        );
        await _fault(
          GenerationFaultPoint.afterStageManifest,
          path: _manifestRelativePath,
        );
      }
      final journal = _Journal(
        phase: 'staged',
        entries: journalEntries,
        manifest: manifestJournal,
      );
      await _fault(GenerationFaultPoint.beforePersistJournal);
      await _writeJournal(journal);
      await _fault(GenerationFaultPoint.afterPersistJournal);
      await _writeJournal(journal.withPhase('committing'));

      for (final entry in journalEntries) {
        await _commitEntry(entry);
      }
      if (manifestJournal != null) {
        await _commitEntry(manifestJournal, manifest: true);
      }
      await _validateCommitted(journal);
      await _writeJournal(journal.withPhase('committed'));
      await _fault(GenerationFaultPoint.beforeCleanup);
      await _transaction.delete(recursive: true);
      await _fault(GenerationFaultPoint.afterCleanup);
      await _journal.delete();
    } on Object catch (error) {
      final original = error;
      try {
        if (await _journal.exists()) {
          await recover();
        } else if (await _transaction.exists()) {
          await _transaction.delete(recursive: true);
        }
      } on GenerationException catch (recovery) {
        throw GenerationException(
          'Generation commit failed and recovery is incomplete.',
          kind: GenerationFailureKind.recovery,
          recoveryPaths: recovery.recoveryPaths,
        );
      }
      if (original is GenerationException) throw original;
      throw GenerationException(
        'Generation commit failed: ${original.runtimeType}.',
        kind: GenerationFailureKind.io,
      );
    }

    return GenerationResult(
      plan: resolved,
      dryRun: false,
      createdPaths: <String>[
        for (final operation in resolved.creates)
          operation.operation.relativePath,
      ],
      updatedPaths: <String>[
        for (final operation in resolved.updates)
          operation.operation.relativePath,
      ],
      deletedPaths: <String>[
        for (final operation in resolved.deletes)
          operation.operation.relativePath,
      ],
    );
  }

  /// Restores exact pre-transaction bytes or validates a completed commit.
  Future<void> recover() async {
    if (!await _journal.exists()) return;
    final journal = await _readJournal();
    if (journal.phase == 'committed') {
      await _validateCommitted(journal);
      if (await _transaction.exists())
        await _transaction.delete(recursive: true);
      await _journal.delete();
      return;
    }

    final conflicts = <String>[];
    for (final entry in <_JournalEntry>[
      ...journal.entries,
      if (journal.manifest case final manifest?) manifest,
    ]) {
      await _validateRollbackEntry(entry, conflicts);
    }
    if (conflicts.isNotEmpty) {
      throw GenerationException(
        'Interrupted generation contains concurrent or consumer changes.',
        kind: GenerationFailureKind.recovery,
        recoveryPaths: List<String>.unmodifiable(conflicts..sort()),
      );
    }

    for (final entry in <_JournalEntry>[
      if (journal.manifest case final manifest?) manifest,
      ...journal.entries.reversed,
    ]) {
      await _rollbackEntry(entry);
    }
    if (await _transaction.exists()) await _transaction.delete(recursive: true);
    await _journal.delete();
  }

  Future<void> _commitEntry(
    _JournalEntry entry, {
    bool manifest = false,
  }) async {
    await _validateNoSymlinkPath(entry.path);
    final destination = File(_resolve(entry.path));
    if (entry.beforeExists) {
      if (!await destination.exists() ||
          await _rawDigest(destination) != entry.beforeDigest) {
        throw GenerationException(
          'Destination changed during commit: ${entry.path}.',
          recoveryPaths: <String>[entry.path],
        );
      }
      final backup = File(_backupPath(entry.path));
      await backup.parent.create(recursive: true);
      await _fault(GenerationFaultPoint.beforeBackup, path: entry.path);
      await destination.rename(backup.path);
      if (await _rawDigest(backup) != entry.beforeDigest) {
        throw GenerationException(
          'Backup validation failed: ${entry.path}.',
          kind: GenerationFailureKind.io,
          recoveryPaths: <String>[entry.path],
        );
      }
      await _fault(GenerationFaultPoint.afterBackup, path: entry.path);
    } else if (await destination.exists()) {
      throw GenerationException(
        'Destination appeared during commit: ${entry.path}.',
        recoveryPaths: <String>[entry.path],
      );
    }
    if (!entry.afterExists) return;
    final staged = File(manifest ? _stageManifestPath : _stagePath(entry.path));
    if (!await staged.exists() ||
        await _rawDigest(staged) != entry.afterDigest) {
      throw GenerationException(
        'Staged output validation failed: ${entry.path}.',
        kind: GenerationFailureKind.io,
        recoveryPaths: <String>[entry.path],
      );
    }
    await destination.parent.create(recursive: true);
    await _fault(
      manifest
          ? GenerationFaultPoint.beforeManifestReplacement
          : GenerationFaultPoint.beforeReplacement,
      path: entry.path,
    );
    await staged.rename(destination.path);
    await _fault(
      manifest
          ? GenerationFaultPoint.afterManifestReplacement
          : GenerationFaultPoint.afterReplacement,
      path: entry.path,
    );
  }

  Future<void> _fault(GenerationFaultPoint point, {String? path}) async {
    final injector = _faultInjector;
    if (injector == null) return;
    await injector(GenerationFaultEvent(point, path: path));
  }

  Future<void> _validateCommitted(_Journal journal) async {
    final conflicts = <String>[];
    for (final entry in <_JournalEntry>[
      ...journal.entries,
      if (journal.manifest case final manifest?) manifest,
    ]) {
      final destination = File(_resolve(entry.path));
      if (entry.afterExists) {
        if (!await destination.exists() ||
            await _rawDigest(destination) != entry.afterDigest) {
          conflicts.add(entry.path);
        }
      } else if (await destination.exists()) {
        conflicts.add(entry.path);
      }
    }
    if (conflicts.isNotEmpty) {
      throw GenerationException(
        'Committed generation validation failed.',
        kind: GenerationFailureKind.recovery,
        recoveryPaths: conflicts,
      );
    }
  }

  Future<void> _validateRollbackEntry(
    _JournalEntry entry,
    List<String> conflicts,
  ) async {
    final destination = File(_resolve(entry.path));
    final backup = File(_backupPath(entry.path));
    final destinationExists = await destination.exists();
    final backupExists = await backup.exists();
    final destinationDigest = destinationExists
        ? await _rawDigest(destination)
        : null;
    if (entry.beforeExists) {
      if (backupExists) {
        if (await _rawDigest(backup) != entry.beforeDigest ||
            destinationExists &&
                destinationDigest != entry.afterDigest &&
                destinationDigest != entry.beforeDigest) {
          conflicts.add(entry.path);
        }
      } else if (!destinationExists ||
          destinationDigest != entry.beforeDigest) {
        conflicts.add(entry.path);
      }
    } else if (destinationExists && destinationDigest != entry.afterDigest) {
      conflicts.add(entry.path);
    }
  }

  Future<void> _rollbackEntry(_JournalEntry entry) async {
    final destination = File(_resolve(entry.path));
    final backup = File(_backupPath(entry.path));
    if (entry.beforeExists) {
      if (await backup.exists()) {
        if (await destination.exists()) {
          final digest = await _rawDigest(destination);
          if (digest == entry.beforeDigest) {
            await backup.delete();
            return;
          }
          if (digest != entry.afterDigest) {
            throw GenerationException(
              'Concurrent change prevented recovery.',
              kind: GenerationFailureKind.recovery,
              recoveryPaths: <String>[entry.path],
            );
          }
          await destination.delete();
        }
        await destination.parent.create(recursive: true);
        await backup.rename(destination.path);
      }
      return;
    }
    if (await destination.exists()) {
      if (await _rawDigest(destination) != entry.afterDigest) {
        throw GenerationException(
          'Concurrent change prevented recovery.',
          kind: GenerationFailureKind.recovery,
          recoveryPaths: <String>[entry.path],
        );
      }
      await destination.delete();
    }
  }

  Future<_Manifest?> _readManifest() async {
    final type = await FileSystemEntity.type(
      _manifest.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file) {
      throw const GenerationException(
        'Model output manifest must be a regular file.',
        kind: GenerationFailureKind.invalidConfiguration,
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(await _manifest.readAsString());
    } on Object {
      throw const GenerationException(
        'Model output manifest is not valid JSON.',
        kind: GenerationFailureKind.invalidConfiguration,
      );
    }
    if (decoded is! Map<String, Object?> ||
        decoded['schemaVersion'] != 1 ||
        decoded['outputs'] is! List<Object?>) {
      throw const GenerationException(
        'Model output manifest has an unsupported schema.',
        kind: GenerationFailureKind.invalidConfiguration,
      );
    }
    final entries = <_ManifestEntry>[];
    final seen = <String>{};
    for (final raw in decoded['outputs']! as List<Object?>) {
      if (raw is! Map<String, Object?>) {
        throw const GenerationException(
          'Model output manifest contains an invalid entry.',
          kind: GenerationFailureKind.invalidConfiguration,
        );
      }
      final entry = _ManifestEntry.fromJson(raw);
      _validatePath(entry.path);
      _validatePath(entry.source);
      if (entry.path.contains('\\') ||
          entry.source.contains('\\') ||
          !entry.path.endsWith('.dartitect.g.dart') ||
          !seen.add(entry.path)) {
        throw const GenerationException(
          'Model output manifest contains an unsafe or duplicate path.',
          kind: GenerationFailureKind.invalidConfiguration,
        );
      }
      await _validateNoSymlinkPath(entry.path);
      await _validateNoSymlinkPath(entry.source);
      entries.add(entry);
    }
    entries.sort((left, right) => left.path.compareTo(right.path));
    return _Manifest(List<_ManifestEntry>.unmodifiable(entries));
  }

  Future<_Journal> _readJournal() async {
    Object? decoded;
    try {
      decoded = jsonDecode(await _journal.readAsString());
    } on Object {
      throw GenerationException(
        'Generation recovery journal is invalid.',
        kind: GenerationFailureKind.recovery,
        recoveryPaths: <String>[_journalRelativePath],
      );
    }
    try {
      final journal = _Journal.fromJson(decoded);
      for (final entry in <_JournalEntry>[
        ...journal.entries,
        if (journal.manifest case final manifest?) manifest,
      ]) {
        _validatePath(entry.path);
        if (entry.path.contains('\\')) throw const FormatException();
        await _validateNoSymlinkPath(entry.path);
      }
      return journal;
    } on Object {
      throw GenerationException(
        'Generation recovery journal has an unsupported schema.',
        kind: GenerationFailureKind.recovery,
        recoveryPaths: <String>[_journalRelativePath],
      );
    }
  }

  Future<void> _writeJournal(_Journal journal) async {
    await _journal.parent.create(recursive: true);
    final temporary = File('${_journal.path}.tmp');
    await temporary.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(journal.toJson())}\n',
      flush: true,
    );
    if (await _journal.exists()) await _journal.delete();
    await temporary.rename(_journal.path);
  }

  Future<List<String>> _findUnmanagedModelOutputs() async {
    if (!await root.exists()) return <String>[];
    final outputs = <String>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dartitect.g.dart'))
        continue;
      final relative = _relative(entity.path);
      final segments = relative.split('/');
      if (segments.any(
        const <String>{'.dart_tool', '.git', 'build'}.contains,
      )) {
        continue;
      }
      outputs.add(relative);
    }
    outputs.sort();
    return outputs;
  }

  void _validateFullyGenerated(FileGenerationOperation operation) {
    if (!operation.relativePath.endsWith('.dartitect.g.dart') ||
        operation.sourcePath == null ||
        operation.inputSignature == null ||
        operation.inputSignature!.isEmpty ||
        operation.generatorVersion.isEmpty ||
        operation.inputSchemaVersion <= 0) {
      throw GenerationException(
        'Fully-generated operation metadata is incomplete: '
        '${operation.relativePath}.',
        kind: GenerationFailureKind.invalidConfiguration,
      );
    }
    _validatePath(operation.sourcePath!);
    if (operation.sourcePath!.contains('\\')) {
      throw const GenerationException(
        'Fully-generated source paths must be normalized.',
        kind: GenerationFailureKind.invalidConfiguration,
      );
    }
  }

  void _validatePath(String path) {
    if (path.isEmpty ||
        path.startsWith('/') ||
        path.startsWith('\\') ||
        RegExp(r'^[A-Za-z]:').hasMatch(path)) {
      throw GenerationException(
        'Path must be relative: "$path".',
        kind: GenerationFailureKind.invalidConfiguration,
      );
    }
    final segments = path.replaceAll('\\', '/').split('/');
    if (segments.any(
      (segment) => segment.isEmpty || segment == '.' || segment == '..',
    )) {
      throw GenerationException(
        'Unsafe path: "$path".',
        kind: GenerationFailureKind.invalidConfiguration,
      );
    }
  }

  Future<void> _validateNoSymlinkPath(String path) async {
    final segments = path.replaceAll('\\', '/').split('/');
    var current = root.path;
    for (var index = 0; index < segments.length; index += 1) {
      current = _join(current, segments[index]);
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw GenerationException(
          'Path crosses a symbolic link: "$path".',
          kind: GenerationFailureKind.invalidConfiguration,
        );
      }
      if (index < segments.length - 1 &&
          type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
        throw GenerationException(
          'Path parent is not a directory: "$path".',
          kind: GenerationFailureKind.invalidConfiguration,
        );
      }
    }
  }

  _ManifestEntry _entryFor(FileGenerationOperation operation) => _ManifestEntry(
    path: operation.relativePath,
    source: operation.sourcePath!,
    generatorVersion: operation.generatorVersion,
    inputSchemaVersion: operation.inputSchemaVersion,
    inputDigest: _textDigest(_canonicalText(operation.inputSignature!)),
    outputDigest: _textDigest(_canonicalText(operation.content)),
  );

  String _encodeManifest(List<_ManifestEntry> entries) =>
      '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'schemaVersion': 1,
        'generator': 'dartitect model',
        'outputs': <Object?>[for (final entry in entries) entry.toJson()],
      })}\n';

  String _resolve(String path) => _join(root.path, path);

  String _relative(String path) => path
      .substring(root.path.length + 1)
      .replaceAll(Platform.pathSeparator, '/');

  String _stagePath(String path) =>
      _join(_transaction.path, 'stage/outputs/$path');

  String _backupPath(String path) => _join(_transaction.path, 'backup/$path');

  String get _stageManifestPath =>
      _join(_transaction.path, 'stage/model-outputs.json');

  File get _manifest => File(_resolve(_manifestRelativePath));

  File get _journal => File(_resolve(_journalRelativePath));

  Directory get _transaction =>
      Directory(_resolve('.dartitect/generation-transaction'));

  static const String _manifestRelativePath = '.dartitect/model-outputs.json';
  static const String _journalRelativePath =
      '.dartitect/generation-journal.json';

  static String _join(String left, String right) =>
      '$left${Platform.pathSeparator}${right.replaceAll('/', Platform.pathSeparator)}';
}

final class _Manifest {
  const _Manifest(this.entries);

  final List<_ManifestEntry> entries;
}

final class _ManifestEntry {
  const _ManifestEntry({
    required this.path,
    required this.source,
    required this.generatorVersion,
    required this.inputSchemaVersion,
    required this.inputDigest,
    required this.outputDigest,
  });

  factory _ManifestEntry.fromJson(Map<String, Object?> json) {
    final path = json['path'];
    final source = json['source'];
    final generatorVersion = json['generatorVersion'];
    final inputSchemaVersion = json['inputSchemaVersion'];
    final inputDigest = json['inputDigest'];
    final outputDigest = json['outputDigest'];
    final digest = RegExp(r'^[0-9a-f]{64}$');
    if (path is! String ||
        source is! String ||
        generatorVersion is! String ||
        generatorVersion.isEmpty ||
        inputSchemaVersion is! int ||
        inputSchemaVersion <= 0 ||
        inputDigest is! String ||
        !digest.hasMatch(inputDigest) ||
        outputDigest is! String ||
        !digest.hasMatch(outputDigest)) {
      throw const FormatException('Invalid model manifest entry.');
    }
    return _ManifestEntry(
      path: path,
      source: source,
      generatorVersion: generatorVersion,
      inputSchemaVersion: inputSchemaVersion,
      inputDigest: inputDigest,
      outputDigest: outputDigest,
    );
  }

  final String path;
  final String source;
  final String generatorVersion;
  final int inputSchemaVersion;
  final String inputDigest;
  final String outputDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'source': source,
    'generatorVersion': generatorVersion,
    'inputSchemaVersion': inputSchemaVersion,
    'inputDigest': inputDigest,
    'outputDigest': outputDigest,
  };

  @override
  bool operator ==(Object other) =>
      other is _ManifestEntry &&
      path == other.path &&
      source == other.source &&
      generatorVersion == other.generatorVersion &&
      inputSchemaVersion == other.inputSchemaVersion &&
      inputDigest == other.inputDigest &&
      outputDigest == other.outputDigest;

  @override
  int get hashCode => Object.hash(
    path,
    source,
    generatorVersion,
    inputSchemaVersion,
    inputDigest,
    outputDigest,
  );
}

final class _Journal {
  const _Journal({
    required this.phase,
    required this.entries,
    required this.manifest,
  });

  factory _Journal.fromJson(Object? value) {
    if (value is! Map<String, Object?> ||
        value['schemaVersion'] != 2 ||
        value['phase'] is! String ||
        !const <String>{
          'staged',
          'committing',
          'committed',
        }.contains(value['phase']) ||
        value['entries'] is! List<Object?>) {
      throw const FormatException('Invalid journal.');
    }
    return _Journal(
      phase: value['phase']! as String,
      entries: <_JournalEntry>[
        for (final raw in value['entries']! as List<Object?>)
          _JournalEntry.fromJson(raw),
      ],
      manifest: value['manifest'] == null
          ? null
          : _JournalEntry.fromJson(value['manifest']),
    );
  }

  final String phase;
  final List<_JournalEntry> entries;
  final _JournalEntry? manifest;

  _Journal withPhase(String value) =>
      _Journal(phase: value, entries: entries, manifest: manifest);

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 2,
    'phase': phase,
    'entries': <Object?>[for (final entry in entries) entry.toJson()],
    'manifest': manifest?.toJson(),
  };
}

final class _JournalEntry {
  const _JournalEntry({
    required this.path,
    required this.disposition,
    required this.beforeExists,
    required this.beforeDigest,
    required this.afterExists,
    required this.afterDigest,
  });

  factory _JournalEntry.fromJson(Object? value) {
    if (value is! Map<String, Object?> ||
        value['path'] is! String ||
        value['disposition'] is! String ||
        value['beforeExists'] is! bool ||
        value['afterExists'] is! bool) {
      throw const FormatException('Invalid journal entry.');
    }
    final disposition = GenerationDisposition.values
        .where((item) => item.name == value['disposition'])
        .firstOrNull;
    final beforeDigest = value['beforeDigest'];
    final afterDigest = value['afterDigest'];
    final digest = RegExp(r'^[0-9a-f]{64}$');
    if (disposition == null ||
        beforeDigest != null &&
            (beforeDigest is! String || !digest.hasMatch(beforeDigest)) ||
        afterDigest != null &&
            (afterDigest is! String || !digest.hasMatch(afterDigest))) {
      throw const FormatException('Invalid journal digest.');
    }
    final entry = _JournalEntry(
      path: value['path']! as String,
      disposition: disposition,
      beforeExists: value['beforeExists']! as bool,
      beforeDigest: beforeDigest as String?,
      afterExists: value['afterExists']! as bool,
      afterDigest: afterDigest as String?,
    );
    if (entry.beforeExists != (entry.beforeDigest != null) ||
        entry.afterExists != (entry.afterDigest != null)) {
      throw const FormatException('Journal existence/digest mismatch.');
    }
    return entry;
  }

  final String path;
  final GenerationDisposition disposition;
  final bool beforeExists;
  final String? beforeDigest;
  final bool afterExists;
  final String? afterDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'disposition': disposition.name,
    'beforeExists': beforeExists,
    'beforeDigest': beforeDigest,
    'afterExists': afterExists,
    'afterDigest': afterDigest,
  };
}

String _canonicalText(String content) {
  final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  return normalized.endsWith('\n') ? normalized : '$normalized\n';
}

bool _equivalent(String left, String right) =>
    _canonicalText(left) == _canonicalText(right);

String _textDigest(String content) =>
    sha256.convert(utf8.encode(content)).toString();

Future<String> _canonicalFileDigest(File file) async =>
    _textDigest(_canonicalText(await file.readAsString()));

Future<String> _rawDigest(File file) async =>
    sha256.convert(await file.readAsBytes()).toString();

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
