import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:crypto/crypto.dart';
import 'package:dartitect/dartitect.dart'
    show
        CancellationException,
        CancellationRegistration,
        CancellationSignal,
        CancellationSource;

import '../config/dartitect_config.dart';
import '../diagnostics/models.dart';
import '../policy/ecosystem_policy.dart';
import '../rules/boundary_rules.dart';

/// Facts and diagnostics produced by the read-only Stage 1 scanner.
final class ProjectScan {
  /// Creates scan results.
  const ProjectScan({
    required this.packageName,
    required this.dependencies,
    required this.features,
    required this.platforms,
    required this.capabilities,
    required this.findings,
    required this.violations,
    required this.dartFileCount,
    required this.suppressionCount,
  });

  /// Name parsed conservatively from pubspec.yaml.
  final String? packageName;

  /// Runtime and development dependency names.
  final List<String> dependencies;

  /// Feature directory names under lib/features.
  final List<String> features;

  /// Detected Flutter platform folders.
  final List<String> platforms;

  /// Detected architectural capabilities.
  final List<String> capabilities;

  /// Scanner limitations and environment findings.
  final List<DartitectFinding> findings;

  /// Architecture boundary violations.
  final List<DartitectFinding> violations;

  /// Number of analyzed, non-generated Dart files.
  final int dartFileCount;

  /// Number of config and inline architecture suppressions observed.
  final int suppressionCount;

  /// Stable machine representation used by progressive scan terminals.
  Map<String, Object?> toJson() => <String, Object?>{
    if (packageName != null) 'packageName': packageName,
    'dependencies': dependencies,
    'features': features,
    'platforms': platforms,
    'capabilities': capabilities,
    'findings': findings.map((finding) => finding.toJson()).toList(),
    'violations': violations.map((finding) => finding.toJson()).toList(),
    'dartFileCount': dartFileCount,
    'suppressionCount': suppressionCount,
  };
}

/// Base event for the progressive scanner protocol.
sealed class ProjectScanEvent {
  const ProjectScanEvent({required this.timestamp});

  /// JSON Lines event schema.
  static const int schemaVersion = 1;

  /// UTC event timestamp.
  final DateTime timestamp;

  /// Stable event discriminator.
  String get kind;

  /// Stable JSON Lines representation.
  Map<String, Object?> toJson();

  Map<String, Object?> _baseJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'event': kind,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// A progressive scan was admitted.
final class ProjectScanStarted extends ProjectScanEvent {
  /// Creates a start event.
  const ProjectScanStarted({required super.timestamp});

  @override
  String get kind => 'started';

  @override
  Map<String, Object?> toJson() => _baseJson();
}

/// One project-relative Dart path was discovered.
final class ProjectScanFileDiscovered extends ProjectScanEvent {
  /// Creates a deterministic discovery event.
  const ProjectScanFileDiscovered({
    required super.timestamp,
    required this.path,
    required this.index,
    required this.total,
  });

  /// Project-relative path.
  final String path;

  /// One-based discovery index.
  final int index;

  /// Total discovered analyzable files.
  final int total;

  @override
  String get kind => 'file-discovered';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ..._baseJson(),
    'path': path,
    'index': index,
    'total': total,
  };
}

/// One discovered file completed semantic analysis.
final class ProjectScanFileAnalyzed extends ProjectScanEvent {
  /// Creates a deterministic analyzed-file event.
  const ProjectScanFileAnalyzed({
    required super.timestamp,
    required this.path,
    required this.index,
    required this.total,
    required this.cacheHit,
  });

  /// Project-relative path.
  final String path;

  /// One-based analyzed index.
  final int index;

  /// Total discovered analyzable files.
  final int total;

  /// Whether immutable source facts came from [ProjectSourceIndex].
  final bool cacheHit;

  @override
  String get kind => 'file-analyzed';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ..._baseJson(),
    'path': path,
    'index': index,
    'total': total,
    'cacheHit': cacheHit,
  };
}

/// One deterministic finding or violation was emitted.
final class ProjectScanFinding extends ProjectScanEvent {
  /// Creates a finding event.
  const ProjectScanFinding({
    required super.timestamp,
    required this.finding,
    required this.isViolation,
  });

  /// Immutable scanner diagnostic.
  final DartitectFinding finding;

  /// Whether this diagnostic is an architecture violation.
  final bool isViolation;

  @override
  String get kind => 'finding';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ..._baseJson(),
    'isViolation': isViolation,
    'finding': finding.toJson(),
  };
}

/// Terminal successful progressive scan event.
final class ProjectScanCompleted extends ProjectScanEvent {
  /// Creates a successful terminal event.
  const ProjectScanCompleted({required super.timestamp, required this.scan});

  /// Complete compatibility result.
  final ProjectScan scan;

  @override
  String get kind => 'completed';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ..._baseJson(),
    'scan': scan.toJson(),
  };
}

/// Terminal cooperative-cancellation event.
final class ProjectScanCancelled extends ProjectScanEvent {
  /// Creates a cancellation terminal with payload-free counts.
  const ProjectScanCancelled({
    required super.timestamp,
    required this.discoveredFileCount,
    required this.analyzedFileCount,
  });

  /// Files discovered before cancellation.
  final int discoveredFileCount;

  /// Files analyzed before cancellation.
  final int analyzedFileCount;

  @override
  String get kind => 'cancelled';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ..._baseJson(),
    'discoveredFileCount': discoveredFileCount,
    'analyzedFileCount': analyzedFileCount,
  };
}

/// Bounded LRU of immutable source hashes and semantic facts.
final class ProjectSourceIndex {
  /// Creates a source index with at most [capacity] entries.
  ProjectSourceIndex({this.capacity = 2048}) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'must be positive');
    }
  }

  /// Maximum retained entries.
  final int capacity;

  final LinkedHashMap<String, _CachedSourceFacts> _entries =
      LinkedHashMap<String, _CachedSourceFacts>();
  var _hitCount = 0;
  var _missCount = 0;
  var _evictionCount = 0;

  /// Retained entry count.
  int get length => _entries.length;

  /// Successful content-and-configuration lookups.
  int get hitCount => _hitCount;

  /// Missing or invalidated lookups.
  int get missCount => _missCount;

  /// Least-recently-used entries removed at capacity.
  int get evictionCount => _evictionCount;

  /// Clears retained facts without changing cumulative counters.
  void clear() => _entries.clear();

  _CachedSourceFacts? _lookup(
    String path,
    String contentHash,
    String configurationHash,
  ) {
    final entry = _entries.remove(path);
    if (entry == null ||
        entry.contentHash != contentHash ||
        entry.configurationHash != configurationHash) {
      _missCount += 1;
      return null;
    }
    _entries[path] = entry;
    _hitCount += 1;
    return entry;
  }

  void _store(String path, _CachedSourceFacts facts) {
    _entries.remove(path);
    _entries[path] = facts;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
      _evictionCount += 1;
    }
  }
}

/// Conservative, deterministic, and read-only project scanner.
final class ProjectScanner {
  /// Creates a scanner rooted at [root].
  ProjectScanner(Directory root, {ProjectSourceIndex? sourceIndex})
    : root = root.absolute,
      sourceIndex = sourceIndex ?? ProjectSourceIndex();

  /// Absolute root used internally. Emitted paths are always relative.
  final Directory root;

  /// Bounded immutable-facts cache shared by repeated scans when injected.
  final ProjectSourceIndex sourceIndex;

  static const _platformNames = <String>[
    'android',
    'ios',
    'web',
    'windows',
    'linux',
    'macos',
  ];

  /// Performs a scan without following symlinks or writing any file.
  Future<ProjectScan> scan() async {
    await for (final event in scanEvents()) {
      if (event is ProjectScanCompleted) return event.scan;
      if (event is ProjectScanCancelled) {
        throw const CancellationException('Project scan cancelled.');
      }
    }
    throw StateError('Project scan ended without a terminal event.');
  }

  /// Emits deterministic progressive events and one terminal event.
  Stream<ProjectScanEvent> scanEvents({CancellationSignal? cancellation}) {
    final localCancellation = CancellationSource();
    CancellationRegistration? externalRegistration;
    late final StreamController<ProjectScanEvent> controller;
    var discoveredFileCount = 0;
    var analyzedFileCount = 0;
    controller = StreamController<ProjectScanEvent>(
      onListen: () {
        externalRegistration = cancellation?.register(localCancellation.cancel);
        unawaited(() async {
          try {
            final scan = await _scan(
              cancellation: localCancellation.signal,
              emit: (event) {
                if (event is ProjectScanFileDiscovered) {
                  discoveredFileCount = event.index;
                } else if (event is ProjectScanFileAnalyzed) {
                  analyzedFileCount = event.index;
                }
                if (!controller.isClosed && controller.hasListener) {
                  controller.add(event);
                }
              },
            );
            if (!controller.isClosed && controller.hasListener) {
              controller.add(
                ProjectScanCompleted(
                  timestamp: DateTime.now().toUtc(),
                  scan: scan,
                ),
              );
            }
          } on CancellationException {
            if (!controller.isClosed && controller.hasListener) {
              controller.add(
                ProjectScanCancelled(
                  timestamp: DateTime.now().toUtc(),
                  discoveredFileCount: discoveredFileCount,
                  analyzedFileCount: analyzedFileCount,
                ),
              );
            }
          } catch (error, stackTrace) {
            if (!controller.isClosed && controller.hasListener) {
              controller.addError(error, stackTrace);
            }
          } finally {
            externalRegistration?.dispose();
            if (!controller.isClosed) await controller.close();
          }
        }());
      },
      onCancel: () {
        localCancellation.cancel('Project scan event consumer cancelled.');
      },
    );
    return controller.stream;
  }

  Future<ProjectScan> _scan({
    required CancellationSignal cancellation,
    required void Function(ProjectScanEvent event) emit,
  }) async {
    final scanNow = DateTime.now().toUtc();
    emit(ProjectScanStarted(timestamp: scanNow));
    cancellation.throwIfCancelled();
    if (!await root.exists()) {
      throw FileSystemException('Project root does not exist', root.path);
    }

    final findings = <DartitectFinding>[];
    final violations = <DartitectFinding>[];
    final pubspec = File(_join(root.path, 'pubspec.yaml'));
    String? packageName;
    final dependencies = <String>[];
    if (!await pubspec.exists()) {
      findings.add(
        const DartitectFinding(
          code: 'DT0001',
          severity: FindingSeverity.error,
          message: 'pubspec.yaml was not found at the project root.',
          path: 'pubspec.yaml',
          remediation: 'Run the command from a Dart or Flutter project root.',
        ),
      );
    } else {
      final facts = _parsePubspec(await pubspec.readAsLines());
      packageName = facts.$1;
      dependencies.addAll(facts.$2);
    }
    if (await pubspec.exists()) {
      final policy = await EcosystemPolicy.load(root);
      final audit = await EcosystemDependencyAuditor(root, policy).audit();
      for (final finding in audit.findings) {
        final diagnostic = DartitectFinding(
          code: finding.code,
          severity: finding.severity,
          message: finding.message,
          path:
              finding.directOwners.length == 1 &&
                  finding.directOwners.single == finding.package
              ? 'pubspec.yaml'
              : 'pubspec.lock',
          evidence: finding.directOwners.isEmpty
              ? finding.package
              : '${finding.package} via ${finding.directOwners.join(', ')}',
          remediation: finding.replacement == null
              ? 'Add or repair a scoped ecosystem-policy exception.'
              : 'Use ${finding.replacement}.',
        );
        if (finding.severity == FindingSeverity.error) {
          violations.add(diagnostic);
        } else {
          findings.add(diagnostic);
        }
      }
    }

    final features = await _directChildDirectories('lib/features');
    final configFile = File(_join(root.path, 'dartitect.json'));
    DartitectConfig? config;
    if (await configFile.exists()) {
      try {
        config = await DartitectConfig.load(configFile);
      } on DartitectConfigException catch (error) {
        findings.add(
          DartitectFinding(
            code: 'DT0005',
            severity: FindingSeverity.error,
            message: 'dartitect.json is invalid.',
            path: 'dartitect.json',
            evidence: error.pointer,
            remediation: error.message,
          ),
        );
      }
    }
    final classifier = config == null
        ? DartitectBoundaryClassifier.defaults()
        : DartitectBoundaryClassifier(
            layers: config.layers,
            compositionRoots: config.compositionRoots,
            generatedInfrastructure: config.generatedInfrastructure,
            generatedSuffixes: config.generatedSuffixes,
          );
    final rootPolicy = _BoundaryPolicy(
      rootPath: root.path,
      config: config,
      classifier: classifier,
    );
    var suppressionCount = config?.suppressions.length ?? 0;
    final platforms = <String>[
      for (final name in _platformNames)
        if (await Directory(_join(root.path, name)).exists()) name,
    ];
    final dartFiles = <File>[];
    final fileOwners = <String, _DeclaredScanRoot>{};
    for (final scanRoot in await _declaredScanRoots(
      pubspec,
      rootPackageName: packageName,
      rootPolicy: rootPolicy,
      findings: findings,
    )) {
      await _walkDartFiles(
        scanRoot.directory,
        dartFiles,
        findings,
        owner: scanRoot,
        fileOwners: fileOwners,
        cancellation: cancellation,
      );
    }
    dartFiles.sort((left, right) => left.path.compareTo(right.path));

    for (var index = 0; index < dartFiles.length; index += 1) {
      cancellation.throwIfCancelled();
      emit(
        ProjectScanFileDiscovered(
          timestamp: DateTime.now().toUtc(),
          path: _relative(dartFiles[index].path),
          index: index + 1,
          total: dartFiles.length,
        ),
      );
    }

    var hasBackground = false;
    var hasComposition = false;
    for (var start = 0; start < dartFiles.length; start += 4) {
      cancellation.throwIfCancelled();
      final end = start + 4 < dartFiles.length ? start + 4 : dartFiles.length;
      final analyzed = await Future.wait<_AnalyzedSource>([
        for (var index = start; index < end; index += 1)
          _analyzeSource(
            dartFiles[index],
            fileOwners[dartFiles[index].absolute.path]!,
            scanNow,
          ),
      ]);
      cancellation.throwIfCancelled();
      for (var offset = 0; offset < analyzed.length; offset += 1) {
        final result = analyzed[offset];
        findings.addAll(result.findings);
        violations.addAll(result.violations);
        suppressionCount += result.suppressionCount;
        hasComposition = hasComposition || result.facts.hasComposition;
        hasBackground = hasBackground || result.facts.hasBackground;
        emit(
          ProjectScanFileAnalyzed(
            timestamp: DateTime.now().toUtc(),
            path: result.path,
            index: start + offset + 1,
            total: dartFiles.length,
            cacheHit: result.cacheHit,
          ),
        );
      }
    }

    final capabilities = <String>[
      if (features.isNotEmpty) 'feature_first',
      if (hasComposition) 'explicit_composition',
      if (hasBackground) 'background_isolate',
      if (dependencies.contains('dartitect')) 'dartitect_core',
      if (dependencies.contains('dartitect_flutter')) 'dartitect_flutter',
      if (dependencies.contains('dio') ||
          dependencies.contains('dartitect_dio'))
        'dio',
      if (dependencies.contains('drift') ||
          dependencies.contains('dartitect_drift'))
        'drift',
      if (dependencies.contains('objectbox') ||
          dependencies.contains('dartitect_objectbox'))
        'objectbox',
    ]..sort();

    violations.sort(_compareFinding);
    findings.sort(_compareFinding);
    for (final finding in findings) {
      emit(
        ProjectScanFinding(
          timestamp: DateTime.now().toUtc(),
          finding: finding,
          isViolation: false,
        ),
      );
    }
    for (final violation in violations) {
      emit(
        ProjectScanFinding(
          timestamp: DateTime.now().toUtc(),
          finding: violation,
          isViolation: true,
        ),
      );
    }
    return ProjectScan(
      packageName: packageName,
      dependencies: List<String>.unmodifiable(dependencies..sort()),
      features: features,
      platforms: platforms,
      capabilities: capabilities,
      findings: findings,
      violations: violations,
      dartFileCount: dartFiles.length,
      suppressionCount: suppressionCount,
    );
  }

  Future<_AnalyzedSource> _analyzeSource(
    File file,
    _DeclaredScanRoot owner,
    DateTime scanNow,
  ) async {
    final relativePath = _relative(file.path);
    final policyPath = owner.policy.relative(file.path);
    final sourceConfig = owner.policy.config;
    final source = await file.readAsString();
    final classification = owner.policy.classifier.classify(
      policyPath,
      source: source,
    );
    final contentHash = sha256.convert(utf8.encode(source)).toString();
    final configurationHash = sha256
        .convert(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'config': sourceConfig?.toJson(),
              'packageName': owner.packageName,
              'policyPath': policyPath,
              'layers': classification.layers.toList()..sort(),
              'composition': classification.isCompositionRoot,
              'generated': classification.isGeneratedInfrastructure,
              'activeSuppressions': <Object?>[
                for (final suppression
                    in sourceConfig?.suppressions ??
                        const <DartitectSuppression>[])
                  <String, Object?>{
                    'code': suppression.code,
                    'path': suppression.path,
                    'active': !suppression.isExpiredAt(scanNow),
                  },
              ],
            }),
          ),
        )
        .toString();
    final cached = sourceIndex._lookup(
      relativePath,
      contentHash,
      configurationHash,
    );
    if (cached != null) {
      return _AnalyzedSource(
        path: relativePath,
        facts: cached.facts,
        findings: cached.findings,
        violations: cached.violations,
        suppressionCount: cached.suppressionCount,
        cacheHit: true,
      );
    }

    final localFindings = <DartitectFinding>[];
    final localViolations = <DartitectFinding>[];
    final suppressions = _parseSuppressions(
      source.split(RegExp(r'\r?\n')),
      path: relativePath,
      findings: localFindings,
    );
    final suppressionCount = suppressions.values.fold<int>(
      0,
      (total, codes) => total + codes.length,
    );
    final parsed = parseString(
      content: source,
      path: file.path,
      throwIfDiagnostics: false,
    );
    final facts = _inspectUnit(
      parsed.unit,
      source: source,
      lineNumberAt: (offset) => parsed.lineInfo.getLocation(offset).lineNumber,
      path: relativePath,
      packageName: owner.packageName,
      classification: classification,
      nativeStrict: sourceConfig?.profile == nativeStrictProfile,
      isSuppressed: (code, line) {
        final inline = <String>{
          ...?suppressions[line - 1],
          ...?suppressions[line],
        };
        if (inline.contains(code)) return true;
        return sourceConfig?.suppressions.any(
              (suppression) =>
                  suppression.code == code &&
                  !suppression.isExpiredAt(scanNow) &&
                  dartitectGlobMatches(suppression.path, policyPath),
            ) ??
            false;
      },
      violations: localViolations,
    );
    final immutableFindings = List<DartitectFinding>.unmodifiable(
      localFindings,
    );
    final immutableViolations = List<DartitectFinding>.unmodifiable(
      localViolations,
    );
    sourceIndex._store(
      relativePath,
      _CachedSourceFacts(
        contentHash: contentHash,
        configurationHash: configurationHash,
        facts: facts,
        findings: immutableFindings,
        violations: immutableViolations,
        suppressionCount: suppressionCount,
      ),
    );
    return _AnalyzedSource(
      path: relativePath,
      facts: facts,
      findings: immutableFindings,
      violations: immutableViolations,
      suppressionCount: suppressionCount,
      cacheHit: false,
    );
  }

  _SemanticFacts _inspectUnit(
    CompilationUnit unit, {
    required String source,
    required int Function(int offset) lineNumberAt,
    required String path,
    required String? packageName,
    required DartitectSourceClassification classification,
    required bool nativeStrict,
    required bool Function(String code, int line) isSuppressed,
    required List<DartitectFinding> violations,
  }) {
    final segments = path.replaceAll('\\', '/').split('/');
    final fileName = segments.last;
    final isViewModel =
        fileName.endsWith('_view_model.dart') || fileName.contains('viewmodel');
    final isRepositoryOrService =
        segments.any(
          const <String>{
            'repository',
            'repositories',
            'service',
            'services',
          }.contains,
        ) ||
        fileName.endsWith('_repository.dart') ||
        fileName.endsWith('_service.dart');
    final declaredTypes = <String>{
      for (final declaration in unit.declarations)
        if (declaration is ClassDeclaration)
          declaration.namePart.typeName.lexeme
        else if (declaration is EnumDeclaration)
          declaration.namePart.typeName.lexeme
        else if (declaration is MixinDeclaration)
          declaration.name.lexeme
        else if (declaration is ExtensionTypeDeclaration)
          declaration.namePart.typeName.lexeme
        else if (declaration is GenericTypeAlias)
          declaration.name.lexeme,
    };
    final topLevelFunctions = <String>{
      for (final declaration in unit.declarations)
        if (declaration is FunctionDeclaration) declaration.name.lexeme,
    };

    final visitor = _SemanticBoundaryVisitor(
      path: path,
      packageName: packageName,
      classification: classification,
      nativeStrict: nativeStrict,
      isViewModel: isViewModel,
      isRepositoryOrService: isRepositoryOrService,
      declaredTypes: declaredTypes,
      topLevelFunctions: topLevelFunctions,
      usesPrivacyRuntime: RegExp(r'\bObservabilityRuntime\s*\.\s*withPrivacy\b')
          .hasMatch(source),
      usesSafeDioInterceptor: RegExp(r'\bDioObservabilityInterceptor\b')
          .hasMatch(source),
      lineNumberAt: lineNumberAt,
      isSuppressed: isSuppressed,
      addViolation: violations.add,
      createViolation: _violation,
    );
    unit.accept(visitor);
    return _SemanticFacts(
      hasComposition:
          visitor.hasComposition || classification.isCompositionRoot,
      hasBackground: visitor.hasBackground,
    );
  }

  DartitectFinding _violation(
    String code,
    String message,
    String path,
    int line,
    String evidence,
  ) => DartitectFinding(
    code: code,
    severity: FindingSeverity.error,
    message: message,
    path: path,
    line: line,
    evidence: evidence.trim(),
    remediation:
        'Move the dependency to a composition or infrastructure boundary.',
  );

  Future<void> _walkDartFiles(
    Directory directory,
    List<File> output,
    List<DartitectFinding> findings, {
    required _DeclaredScanRoot owner,
    required Map<String, _DeclaredScanRoot> fileOwners,
    required CancellationSignal cancellation,
  }) async {
    cancellation.throwIfCancelled();
    final relativeDirectory = _relative(directory.path);
    final normalizedDirectory = relativeDirectory.replaceAll('\\', '/');
    if (normalizedDirectory == 'tool/agent_evals/fixtures' ||
        normalizedDirectory == 'tool/agent_evals/scorers') {
      // The evaluation corpus intentionally contains invalid Dart examples.
      // Its dedicated checker validates these fixtures and scorers; treating
      // them as project sources would make the general architecture scan
      // report the failures that the corpus is designed to exercise.
      return;
    }
    if (relativeDirectory != '.' &&
        await File(_join(directory.path, 'pubspec.yaml')).exists()) {
      return;
    }
    final segments = normalizedDirectory.split('/');
    if (segments.any(
      const <String>{
        '.dart_tool',
        '.git',
        '.symlinks',
        'build',
        'ephemeral',
        'Pods',
      }.contains,
    )) {
      return;
    }
    List<FileSystemEntity> entities;
    try {
      entities = await directory.list(followLinks: false).toList();
    } on FileSystemException catch (error) {
      findings.add(
        DartitectFinding(
          code: 'DT0002',
          severity: FindingSeverity.warning,
          message: 'A directory could not be read.',
          path: relativeDirectory,
          evidence: error.osError?.message,
          remediation: 'Check filesystem permissions and scan again.',
        ),
      );
      return;
    }
    entities.sort((left, right) => left.path.compareTo(right.path));
    for (final entity in entities) {
      cancellation.throwIfCancelled();
      if (entity is Link) {
        findings.add(
          DartitectFinding(
            code: 'DT0003',
            severity: FindingSeverity.info,
            message: 'Symbolic link skipped by the read-only scanner.',
            path: _relative(entity.path),
          ),
        );
      } else if (entity is Directory) {
        await _walkDartFiles(
          entity,
          output,
          findings,
          owner: owner,
          fileOwners: fileOwners,
          cancellation: cancellation,
        );
      } else if (entity is File && entity.path.endsWith('.dart')) {
        output.add(entity);
        fileOwners[entity.absolute.path] = owner;
      }
    }
  }

  Future<List<_DeclaredScanRoot>> _declaredScanRoots(
    File pubspec, {
    required String? rootPackageName,
    required _BoundaryPolicy rootPolicy,
    required List<DartitectFinding> findings,
  }) async {
    final roots = <String, _DeclaredScanRoot>{};
    Future<void> addPackage(Directory package) async {
      final packagePubspec = File(_join(package.path, 'pubspec.yaml'));
      final packageFacts = await packagePubspec.exists()
          ? _parsePubspec(await packagePubspec.readAsLines())
          : (null, <String>[]);
      final packageName = packageFacts.$1 ?? rootPackageName;
      var policy = rootPolicy;
      if (package.absolute.path != root.absolute.path) {
        final packageConfig = File(_join(package.path, 'dartitect.json'));
        if (await packageConfig.exists()) {
          try {
            final parsed = await DartitectConfig.load(packageConfig);
            policy = _BoundaryPolicy(
              rootPath: package.path,
              config: parsed,
              classifier: DartitectBoundaryClassifier(
                layers: parsed.layers,
                compositionRoots: parsed.compositionRoots,
                generatedInfrastructure: parsed.generatedInfrastructure,
                generatedSuffixes: parsed.generatedSuffixes,
              ),
            );
          } on DartitectConfigException catch (error) {
            findings.add(
              DartitectFinding(
                code: 'DT0005',
                severity: FindingSeverity.error,
                message: 'dartitect.json is invalid.',
                path: _relative(packageConfig.path),
                evidence: error.pointer,
                remediation: error.message,
              ),
            );
          }
        }
      }
      for (final name in const <String>[
        'lib',
        'bin',
        'test',
        'integration_test',
        'tool',
      ]) {
        final directory = Directory(_join(package.path, name));
        if (await directory.exists())
          roots[directory.absolute.path] = _DeclaredScanRoot(
            directory: directory,
            packageName: packageName,
            policy: policy,
          );
      }
    }

    await addPackage(root);
    if (await pubspec.exists()) {
      final lines = await pubspec.readAsLines();
      var inWorkspace = false;
      for (final line in lines) {
        if (line.trim() == 'workspace:') {
          inWorkspace = true;
          continue;
        }
        if (inWorkspace && line.isNotEmpty && !line.startsWith(' ')) break;
        final match = inWorkspace
            ? RegExp(r'^\s*-\s+([^#]+?)\s*$').firstMatch(line)
            : null;
        final pattern = match
            ?.group(1)
            ?.replaceAll(RegExp(r'''^['"]|['"]$'''), '');
        if (pattern == null) continue;
        if (pattern.endsWith('/*')) {
          final parent = Directory(
            _join(root.path, pattern.substring(0, pattern.length - 2)),
          );
          if (!await parent.exists()) continue;
          await for (final child in parent.list(followLinks: false)) {
            if (child is Directory &&
                await File(_join(child.path, 'pubspec.yaml')).exists()) {
              await addPackage(child);
            }
          }
        } else {
          final package = Directory(_join(root.path, pattern));
          if (await File(_join(package.path, 'pubspec.yaml')).exists()) {
            await addPackage(package);
          }
        }
      }
    }
    final result = roots.values.toList()
      ..sort(
        (left, right) => left.directory.path.compareTo(right.directory.path),
      );
    return result;
  }

  Map<int, Set<String>> _parseSuppressions(
    List<String> lines, {
    required String path,
    required List<DartitectFinding> findings,
  }) {
    final result = <int, Set<String>>{};
    final marker = RegExp(r'dartitect-ignore:\s*(DT\d{4})(.*)$');
    final valid = RegExp(r'^\s*--\s*(\S.{2,})\s*$');
    for (var index = 0; index < lines.length; index += 1) {
      final match = marker.firstMatch(lines[index]);
      if (match == null) continue;
      final code = match.group(1)!;
      if (!valid.hasMatch(match.group(2)!)) {
        findings.add(
          DartitectFinding(
            code: 'DT0004',
            severity: FindingSeverity.warning,
            message: 'A local suppression requires a justification.',
            path: path,
            line: index + 1,
            evidence: code,
            remediation: 'Use `dartitect-ignore: $code -- reason`.',
          ),
        );
        continue;
      }
      result.putIfAbsent(index + 1, () => <String>{}).add(code);
    }
    return result;
  }

  Future<List<String>> _directChildDirectories(String relative) async {
    final directory = Directory(_join(root.path, relative));
    if (!await directory.exists()) return <String>[];
    final names = <String>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is Directory) {
        names.add(
          entity.uri.pathSegments.where((segment) => segment.isNotEmpty).last,
        );
      }
    }
    names.sort();
    return names;
  }

  (String?, List<String>) _parsePubspec(List<String> lines) {
    String? name;
    var dependencySection = false;
    final dependencies = <String>[];
    for (final line in lines) {
      final nameMatch = RegExp(r'^name:\s*([A-Za-z0-9_]+)\s*$')
          .firstMatch(line);
      name ??= nameMatch?.group(1);
      if (RegExp(r'^(dependencies|dev_dependencies):\s*$').hasMatch(line)) {
        dependencySection = true;
        continue;
      }
      if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('#')) {
        dependencySection = false;
      }
      if (dependencySection) {
        final match = RegExp(r'^  ([A-Za-z0-9_]+):').firstMatch(line);
        final dependency = match?.group(1);
        if (dependency != null && !dependencies.contains(dependency)) {
          dependencies.add(dependency);
        }
      }
    }
    return (name, dependencies);
  }

  String _relative(String path) {
    final rootPath = root.path.endsWith(Platform.pathSeparator)
        ? root.path
        : '${root.path}${Platform.pathSeparator}';
    if (path == root.path) return '.';
    return path
        .substring(rootPath.length)
        .replaceAll(Platform.pathSeparator, '/');
  }

  static String _join(String left, String right) =>
      '$left${Platform.pathSeparator}${right.replaceAll('/', Platform.pathSeparator)}';

  static int _compareFinding(DartitectFinding left, DartitectFinding right) {
    final path = (left.path ?? '').compareTo(right.path ?? '');
    if (path != 0) return path;
    final line = (left.line ?? 0).compareTo(right.line ?? 0);
    if (line != 0) return line;
    return left.code.compareTo(right.code);
  }
}

final class _DeclaredScanRoot {
  const _DeclaredScanRoot({
    required this.directory,
    required this.packageName,
    required this.policy,
  });

  final Directory directory;
  final String? packageName;
  final _BoundaryPolicy policy;
}

final class _BoundaryPolicy {
  const _BoundaryPolicy({
    required this.rootPath,
    required this.config,
    required this.classifier,
  });

  final String rootPath;
  final DartitectConfig? config;
  final DartitectBoundaryClassifier classifier;

  String relative(String sourcePath) {
    final root = Directory(rootPath).absolute.path.replaceAll('\\', '/');
    final source = File(sourcePath).absolute.path.replaceAll('\\', '/');
    final prefix = root.endsWith('/') ? root : '$root/';
    final comparablePrefix = Platform.isWindows ? prefix.toLowerCase() : prefix;
    final comparableSource = Platform.isWindows ? source.toLowerCase() : source;
    if (comparableSource.startsWith(comparablePrefix)) {
      return source.substring(prefix.length);
    }
    return source;
  }
}

final class _CachedSourceFacts {
  const _CachedSourceFacts({
    required this.contentHash,
    required this.configurationHash,
    required this.facts,
    required this.findings,
    required this.violations,
    required this.suppressionCount,
  });

  final String contentHash;
  final String configurationHash;
  final _SemanticFacts facts;
  final List<DartitectFinding> findings;
  final List<DartitectFinding> violations;
  final int suppressionCount;
}

final class _AnalyzedSource {
  const _AnalyzedSource({
    required this.path,
    required this.facts,
    required this.findings,
    required this.violations,
    required this.suppressionCount,
    required this.cacheHit,
  });

  final String path;
  final _SemanticFacts facts;
  final List<DartitectFinding> findings;
  final List<DartitectFinding> violations;
  final int suppressionCount;
  final bool cacheHit;
}

final class _SemanticFacts {
  const _SemanticFacts({
    required this.hasComposition,
    required this.hasBackground,
  });

  final bool hasComposition;
  final bool hasBackground;
}

final class _SemanticBoundaryVisitor extends RecursiveAstVisitor<void> {
  _SemanticBoundaryVisitor({
    required this.path,
    required this.packageName,
    required this.classification,
    required this.nativeStrict,
    required this.isViewModel,
    required this.isRepositoryOrService,
    required this.declaredTypes,
    required this.topLevelFunctions,
    required this.usesPrivacyRuntime,
    required this.usesSafeDioInterceptor,
    required this.lineNumberAt,
    required this.isSuppressed,
    required this.addViolation,
    required this.createViolation,
  });

  final String path;
  final String? packageName;
  final DartitectSourceClassification classification;
  final bool nativeStrict;
  final bool isViewModel;
  final bool isRepositoryOrService;
  final Set<String> declaredTypes;
  final Set<String> topLevelFunctions;
  final bool usesPrivacyRuntime;
  final bool usesSafeDioInterceptor;
  final int Function(int offset) lineNumberAt;
  final bool Function(String code, int line) isSuppressed;
  final void Function(DartitectFinding finding) addViolation;
  final DartitectFinding Function(
    String code,
    String message,
    String path,
    int line,
    String evidence,
  )
  createViolation;

  var hasComposition = false;
  var hasBackground = false;

  bool get _isDomain => classification.isLayer('domain');
  bool get _isApplication => classification.isLayer('application');
  bool get _isData => classification.isLayer('data');
  bool get _isPresentation => classification.isLayer('presentation');
  bool get _isInfrastructure =>
      classification.isLayer('infrastructure') ||
      packageName != null &&
          DartitectArchitectureRules.infrastructurePackages.contains(
            packageName,
          );

  @override
  void visitImportDirective(ImportDirective node) {
    _inspectUri(node.uri);
    for (final configuration in node.configurations) {
      _inspectUri(configuration.uri);
    }
    super.visitImportDirective(node);
  }

  @override
  void visitExportDirective(ExportDirective node) {
    _inspectUri(node.uri);
    for (final configuration in node.configurations) {
      _inspectUri(configuration.uri);
    }
    super.visitExportDirective(node);
  }

  @override
  void visitNamedType(NamedType node) {
    if (classification.isGeneratedInfrastructure) return;
    final name = node.name.lexeme;
    if (declaredTypes.contains(name)) {
      super.visitNamedType(node);
      return;
    }
    if (name == 'CompositionRoot' || name == 'ResourceOwner') {
      hasComposition = true;
    }
    if (name == 'BuildContext' &&
        (isViewModel || isRepositoryOrService || _isDomain || _isData)) {
      _report(
        DartitectRuleCodes.buildContextBoundary,
        'ViewModels, repositories, services, domain, and data must not use BuildContext.',
        node.offset,
        'BuildContext',
      );
    }
    if (nativeStrict &&
        name == 'DartitectScope' &&
        !classification.isCompositionRoot &&
        !path.endsWith('dartitect_scope.dart')) {
      _report(
        DartitectRuleCodes.scopeBoundary,
        'DartitectScope may be used only by an explicit composition root.',
        node.offset,
        name,
      );
    }
    if (nativeStrict &&
        !classification.isCompositionRoot &&
        !_isInfrastructure &&
        DartitectArchitectureRules.providerTypes.contains(name) &&
        !_providerImportAlreadyReported) {
      _report(
        DartitectRuleCodes.providerTypeBoundary,
        'Provider types must remain in infrastructure or composition.',
        node.offset,
        name,
      );
    }
    if (nativeStrict &&
        name != 'BuildContext' &&
        !classification.isCompositionRoot &&
        !_isPresentation &&
        DartitectArchitectureRules.flutterBoundaryTypes.contains(name)) {
      _report(
        DartitectRuleCodes.flutterTypeBoundary,
        'Flutter Widget/router types must remain in View or composition.',
        node.offset,
        name,
      );
    }
    super.visitNamedType(node);
  }

  @override
  void visitAnnotation(Annotation node) {
    if (classification.isGeneratedInfrastructure) return;
    final name = node.name.toSource().split('.').last;
    if (name == 'pragma' &&
        node.arguments?.toSource().contains('vm:entry-point') == true) {
      hasBackground = true;
    }
    if (nativeStrict &&
        DartitectArchitectureRules.architectureCodegenAnnotations.contains(
          name,
        )) {
      _report(
        DartitectRuleCodes.architectureCodegen,
        'Architecture/state code generation is forbidden.',
        node.offset,
        name,
      );
    }
    if (nativeStrict &&
        !_isInfrastructure &&
        DartitectArchitectureRules.providerCodegenAnnotations.contains(name)) {
      _report(
        DartitectRuleCodes.providerCodegenBoundary,
        'Provider code generation belongs in infrastructure.',
        node.offset,
        name,
      );
    }
    super.visitAnnotation(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (classification.isGeneratedInfrastructure) return;
    _inspectPrivacyInvocation(node);
    if (node.target?.toSource() == 'Isolate' &&
        node.methodName.name == 'spawn') {
      hasBackground = true;
    }
    final target = node.target?.toSource();
    final method = node.methodName.name;
    if (nativeStrict &&
        target == 'DartitectScope' &&
        const <String>{'read', 'maybeRead'}.contains(method) &&
        !classification.isCompositionRoot &&
        !path.endsWith('dartitect_scope.dart')) {
      _report(
        DartitectRuleCodes.scopeBoundary,
        'DartitectScope lookup may occur only in a composition root.',
        node.offset,
        '$target.$method',
      );
    }
    final locatorTarget = const <String>{
      'GetIt',
      'getIt',
      'locator',
      'serviceLocator',
    }.contains(target);
    final locatorCall = const <String>{
      'call',
      'get',
      'getByType',
      'lookupByType',
    }.contains(method);
    final topLevelLocatorCall =
        target == null &&
        const <String>{
          'getIt',
          'locator',
          'serviceLocator',
          'getByType',
          'lookupByType',
        }.contains(method);
    if (nativeStrict &&
        !topLevelFunctions.contains(method) &&
        (locatorTarget && locatorCall || topLevelLocatorCall)) {
      _report(
        DartitectRuleCodes.serviceLocator,
        'Service locator and lookup-by-type access are forbidden.',
        node.offset,
        '${target ?? ''}.$method',
      );
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    if (!classification.isGeneratedInfrastructure &&
        _sensitiveInterpolation.hasMatch(node.toSource()) &&
        _isLoggerInterpolation(node)) {
      _report(
        DartitectRuleCodes.sensitiveLogInterpolation,
        'Sensitive HTTP or credential data must not be interpolated into a logger message.',
        node.offset,
        'interpolated logger message',
      );
    }
    super.visitStringInterpolation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (classification.isGeneratedInfrastructure) {
      super.visitInstanceCreationExpression(node);
      return;
    }
    _inspectPrivacyConstruction(node);
    if (!nativeStrict || !_importsDartitectFlutter(node)) {
      super.visitInstanceCreationExpression(node);
      return;
    }
    final constructor = node.constructorName;
    final host = constructor.type.name.lexeme;
    if (constructor.name?.name == 'value' &&
        DartitectArchitectureRules.borrowingValueHosts.contains(host)) {
      NamedArgument? valueArgument;
      for (final argument in node.argumentList.arguments) {
        if (argument is NamedArgument && argument.name.lexeme == 'value') {
          valueArgument = argument;
          break;
        }
      }
      final value = valueArgument?.argumentExpression;
      final disposable = _temporaryConstructedType(value);
      if (disposable != null &&
          DartitectArchitectureRules.knownDisposableTypes.contains(
            disposable,
          )) {
        _report(
          DartitectRuleCodes.temporaryDisposableHostValue,
          'A borrowing host .value constructor must not receive an inline disposable.',
          value!.offset,
          '$host.value',
        );
      }
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMapLiteralEntry(MapLiteralEntry node) {
    if (!classification.isGeneratedInfrastructure &&
        _isUnclassifiedCustomCapture(node)) {
      _report(
        DartitectRuleCodes.unclassifiedCustomCapture,
        'A custom telemetry value requires ObservabilityClassifiedValue.',
        node.value.offset,
        'custom telemetry value',
      );
    }
    super.visitMapLiteralEntry(node);
  }

  void _inspectPrivacyConstruction(InstanceCreationExpression node) {
    final type = node.constructorName.type.name.lexeme;
    final constructorSource = node.constructorName.toSource();
    if (type == 'LogInterceptor' && usesSafeDioInterceptor) {
      _report(
        DartitectRuleCodes.dioLogInterceptorConflict,
        'Dio LogInterceptor bypasses Dartitect classified observability capture.',
        node.offset,
        'LogInterceptor',
      );
    }
    if ((constructorSource == 'ObservabilityRiskAcceptance.explicit' ||
            RegExp(r'\bObservabilityRiskAcceptance\s*\.\s*explicit\s*\(')
                .hasMatch(node.toSource())) &&
        !_isQaSource) {
      _report(
        DartitectRuleCodes.productionRiskAcceptance,
        'ObservabilityRiskAcceptance must be limited to reviewed test or QA source.',
        node.offset,
        'ObservabilityRiskAcceptance.explicit',
      );
    }
    if (usesPrivacyRuntime &&
        constructorSource == type &&
        const <String>{
          'SentryLogSink',
          'SentryErrorReporter',
          'SentryTracer',
        }.contains(type) &&
        _hasRegistrationAncestor(node, const <String>{
          'PreparedLogSinkRegistration',
          'ErrorReporterRegistration',
          'TracerRegistration',
        })) {
      _report(
        DartitectRuleCodes.legacySentryPreparedRegistration,
        'A privacy runtime destination must use a prepared Sentry adapter.',
        node.offset,
        type,
      );
    }
  }

  void _inspectPrivacyInvocation(MethodInvocation node) {
    final target = node.target?.toSource();
    final method = node.methodName.name;
    if (target == null &&
        method == 'LogInterceptor' &&
        usesSafeDioInterceptor) {
      _report(
        DartitectRuleCodes.dioLogInterceptorConflict,
        'Dio LogInterceptor bypasses Dartitect classified observability capture.',
        node.offset,
        'LogInterceptor',
      );
    }
    if (target == 'ObservabilityRiskAcceptance' &&
        method == 'explicit' &&
        !_isQaSource) {
      _report(
        DartitectRuleCodes.productionRiskAcceptance,
        'ObservabilityRiskAcceptance must be limited to reviewed test or QA source.',
        node.offset,
        'ObservabilityRiskAcceptance.explicit',
      );
    }
    if (usesPrivacyRuntime &&
        target == null &&
        const <String>{
          'SentryLogSink',
          'SentryErrorReporter',
          'SentryTracer',
        }.contains(method) &&
        _hasRegistrationAncestor(node, const <String>{
          'PreparedLogSinkRegistration',
          'ErrorReporterRegistration',
          'TracerRegistration',
        })) {
      _report(
        DartitectRuleCodes.legacySentryPreparedRegistration,
        'A privacy runtime destination must use a prepared Sentry adapter.',
        node.offset,
        method,
      );
    }
  }

  bool _isUnclassifiedCustomCapture(MapLiteralEntry entry) {
    final value = entry.value;
    final type = switch (value) {
      InstanceCreationExpression(:final constructorName) =>
        constructorName.type.name.lexeme,
      MethodInvocation(:final target, :final methodName)
          when target == null &&
              !topLevelFunctions.contains(methodName.name) &&
              (declaredTypes.contains(methodName.name) ||
                  _typeLikeName.hasMatch(methodName.name)) =>
        methodName.name,
      _ => null,
    };
    if (type == null) return false;
    if (_safeCaptureTypes.contains(type)) return false;
    var cursor = entry.parent;
    for (var depth = 0; depth < 10 && cursor != null; depth += 1) {
      if (cursor is InstanceCreationExpression &&
          const <String>{
            'ObservabilityContext',
            'ObservabilityLogEvent',
            'ErrorEvent',
          }.contains(cursor.constructorName.type.name.lexeme)) {
        return true;
      }
      if (cursor is MethodInvocation &&
          const <String>{
            'addEvent',
            'event',
            'log',
            'report',
            'setAttribute',
            'startSpan',
          }.contains(cursor.methodName.name)) {
        return true;
      }
      cursor = cursor.parent;
    }
    return false;
  }

  bool _isLoggerInterpolation(AstNode node) {
    var cursor = node.parent;
    for (var depth = 0; depth < 12 && cursor != null; depth += 1) {
      if (cursor is MethodInvocation &&
          const <String>{
            'debug',
            'error',
            'event',
            'fatal',
            'info',
            'log',
            'warning',
          }.contains(cursor.methodName.name)) {
        final target = cursor.target?.toSource().toLowerCase();
        if (target != null && target.endsWith('logger')) return true;
      }
      if (cursor is InstanceCreationExpression &&
          cursor.constructorName.type.name.lexeme == 'ObservabilityLogEvent') {
        return true;
      }
      cursor = cursor.parent;
    }
    return false;
  }

  static bool _hasRegistrationAncestor(
    AstNode node,
    Set<String> acceptedTypes,
  ) {
    var cursor = node.parent;
    for (var depth = 0; depth < 8 && cursor != null; depth += 1) {
      if (cursor is InstanceCreationExpression &&
          acceptedTypes.contains(cursor.constructorName.type.name.lexeme)) {
        return true;
      }
      if (cursor is MethodInvocation &&
          acceptedTypes.contains(cursor.target?.toSource())) {
        return true;
      }
      cursor = cursor.parent;
    }
    return false;
  }

  bool get _isQaSource {
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    final segments = normalized
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    return segments.any(
          const <String>{
            'qa',
            'test',
            'testing',
            'fixture',
            'fixtures',
          }.contains,
        ) ||
        segments.last.endsWith('_qa.dart');
  }

  bool _providerImportAlreadyReported = false;

  void _inspectUri(StringLiteral literal) {
    final uri = literal.stringValue;
    if (uri == null) return;
    final package = RegExp(r'^package:([^/]+)/').firstMatch(uri)?.group(1);
    if (classification.isGeneratedInfrastructure) {
      if (package != null &&
          DartitectArchitectureRules.forbiddenPackages.contains(package)) {
        _report(
          DartitectRuleCodes.forbiddenArchitecture,
          'Architecture framework imports are forbidden.',
          literal.offset,
          uri,
        );
      }
      return;
    }
    final infrastructure =
        package != null &&
        DartitectArchitectureRules.infrastructurePackages.contains(package);
    if (_isDomain && uri.startsWith('package:flutter/')) {
      _report(
        DartitectRuleCodes.domainFlutter,
        'Domain code must not import Flutter.',
        literal.offset,
        uri,
      );
    }
    if ((_isDomain || _isApplication) &&
        (uri.contains('/data/') || infrastructure)) {
      _report(
        DartitectRuleCodes.domainInfrastructure,
        'Domain/application code must not import data implementations or adapters.',
        literal.offset,
        uri,
      );
    }
    if (_isData && uri.contains('/presentation/')) {
      _report(
        DartitectRuleCodes.dataPresentation,
        'Data code must not import presentation.',
        literal.offset,
        uri,
      );
    }
    if ((_isPresentation || isViewModel) &&
        !classification.isCompositionRoot &&
        infrastructure) {
      _report(
        DartitectRuleCodes.presentationInfrastructure,
        'Presentation/ViewModel code must not import infrastructure clients.',
        literal.offset,
        uri,
      );
      _providerImportAlreadyReported = true;
    }
    final importsImplementation =
        uri.contains('/infrastructure/') || uri.contains('/data/');
    final ownOrRelative =
        uri.startsWith('../') ||
        uri.startsWith('./') ||
        package != null && package == packageName;
    if (nativeStrict &&
        importsImplementation &&
        ownOrRelative &&
        !_isInfrastructure &&
        !classification.isCompositionRoot &&
        !_isDomain) {
      _report(
        DartitectRuleCodes.implementationBoundary,
        'Concrete implementations may be imported only by infrastructure or composition.',
        literal.offset,
        uri,
      );
    }
    if (package != null &&
        DartitectArchitectureRules.forbiddenPackages.contains(package)) {
      _report(
        DartitectRuleCodes.forbiddenArchitecture,
        'Architecture framework imports are forbidden.',
        literal.offset,
        uri,
      );
    }
    if (package != null && package != packageName && uri.contains('/src/')) {
      _report(
        DartitectRuleCodes.privateSrc,
        'Private src/ imports from another package are forbidden.',
        literal.offset,
        uri,
      );
    }
  }

  static bool _importsDartitectFlutter(AstNode node) {
    AstNode? current = node;
    while (current != null && current is! CompilationUnit) {
      current = current.parent;
    }
    final unit = current as CompilationUnit?;
    return unit?.directives.whereType<ImportDirective>().any(
          (directive) =>
              directive.uri.stringValue?.startsWith(
                'package:dartitect_flutter/',
              ) ??
              false,
        ) ??
        false;
  }

  static String? _temporaryConstructedType(Expression? expression) =>
      switch (expression) {
        InstanceCreationExpression(:final constructorName) =>
          constructorName.type.name.lexeme,
        MethodInvocation(:final target, :final methodName)
            when target == null =>
          methodName.name,
        _ => null,
      };

  static final _sensitiveInterpolation = RegExp(
    r'\b(authorization|token|password|cookie|body|headers?|query)\b',
    caseSensitive: false,
  );

  static const _safeCaptureTypes = <String>{
    'DateTime',
    'Duration',
    'ObservabilityClassifiedValue',
    'ObservabilityErrorProjection',
    'ObservabilityStackTraceProjection',
    'Uri',
  };

  static final _typeLikeName = RegExp(r'^[A-Z][A-Za-z0-9_]*$');

  void _report(String code, String message, int offset, String evidence) {
    final line = lineNumberAt(offset);
    if (isSuppressed(code, line)) return;
    addViolation(createViolation(code, message, path, line, evidence));
  }
}
