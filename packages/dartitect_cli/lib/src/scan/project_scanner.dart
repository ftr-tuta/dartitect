import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

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
}

/// Conservative, deterministic, and read-only project scanner.
final class ProjectScanner {
  /// Creates a scanner rooted at [root].
  ProjectScanner(Directory root) : root = root.absolute;

  /// Absolute root used internally. Emitted paths are always relative.
  final Directory root;

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
      for (final dependency in dependencies) {
        if (DartitectArchitectureRules.forbiddenPackages.contains(dependency)) {
          violations.add(
            DartitectFinding(
              code: DartitectRuleCodes.forbiddenArchitecture,
              severity: FindingSeverity.error,
              message: 'Forbidden architecture dependency: $dependency.',
              path: 'pubspec.yaml',
              evidence: dependency,
              remediation: 'Use constructor injection and native listenables.',
            ),
          );
        }
      }
    }
    final lockfile = File(_join(root.path, 'pubspec.lock'));
    if (await lockfile.exists()) {
      for (final dependency in _parseLockPackages(
        await lockfile.readAsLines(),
      )) {
        if (DartitectArchitectureRules.forbiddenPackages.contains(dependency)) {
          violations.add(
            DartitectFinding(
              code: DartitectRuleCodes.forbiddenArchitecture,
              severity: FindingSeverity.error,
              message:
                  'Forbidden transitive architecture dependency: $dependency.',
              path: 'pubspec.lock',
              evidence: dependency,
              remediation:
                  'Remove the dependency chain and use Dartitect owned state.',
            ),
          );
        }
      }
    }
    if (await pubspec.exists()) {
      final policy = await EcosystemPolicy.load(root);
      final audit = await EcosystemDependencyAuditor(root, policy).audit();
      for (final finding in audit.findings) {
        violations.add(
          DartitectFinding(
            code: finding.code,
            severity: FindingSeverity.error,
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
          ),
        );
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
          );
    final rootPolicy = _BoundaryPolicy(
      rootPath: root.path,
      config: config,
      classifier: classifier,
    );
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
      );
    }
    dartFiles.sort((left, right) => left.path.compareTo(right.path));

    var hasBackground = false;
    var hasComposition = false;
    for (final file in dartFiles) {
      final relativePath = _relative(file.path);
      final owner = fileOwners[file.absolute.path]!;
      final policyPath = owner.policy.relative(file.path);
      final sourceConfig = owner.policy.config;
      final source = await file.readAsString();
      final lines = source.split(RegExp(r'\r?\n'));
      final suppressions = _parseSuppressions(
        lines,
        path: relativePath,
        findings: findings,
      );
      final parsed = parseString(
        content: source,
        path: file.path,
        throwIfDiagnostics: false,
      );
      final facts = _inspectUnit(
        parsed.unit,
        lineNumberAt: (offset) =>
            parsed.lineInfo.getLocation(offset).lineNumber,
        path: relativePath,
        packageName: owner.packageName,
        classification: owner.policy.classifier.classify(policyPath),
        nativeStrict: sourceConfig?.profile == nativeStrictProfile,
        isSuppressed: (code, line) {
          final inline = <String>{
            ...?suppressions[line - 1],
            ...?suppressions[line],
          };
          if (inline.contains(code)) return true;
          final now = DateTime.now().toUtc();
          return sourceConfig?.suppressions.any(
                (suppression) =>
                    suppression.code == code &&
                    !suppression.isExpiredAt(now) &&
                    dartitectGlobMatches(suppression.path, policyPath),
              ) ??
              false;
        },
        violations: violations,
      );
      hasComposition = hasComposition || facts.hasComposition;
      hasBackground = hasBackground || facts.hasBackground;
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
      if (dependencies.contains('objectbox') ||
          dependencies.contains('dartitect_objectbox'))
        'objectbox',
    ]..sort();

    violations.sort(_compareFinding);
    findings.sort(_compareFinding);
    return ProjectScan(
      packageName: packageName,
      dependencies: List<String>.unmodifiable(dependencies..sort()),
      features: features,
      platforms: platforms,
      capabilities: capabilities,
      findings: findings,
      violations: violations,
      dartFileCount: dartFiles.length,
    );
  }

  _SemanticFacts _inspectUnit(
    CompilationUnit unit, {
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

    final visitor = _SemanticBoundaryVisitor(
      path: path,
      packageName: packageName,
      classification: classification,
      nativeStrict: nativeStrict,
      isViewModel: isViewModel,
      isRepositoryOrService: isRepositoryOrService,
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
  }) async {
    final relativeDirectory = _relative(directory.path);
    if (relativeDirectory != '.' &&
        await File(_join(directory.path, 'pubspec.yaml')).exists()) {
      return;
    }
    final segments = relativeDirectory.replaceAll('\\', '/').split('/');
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
  bool get _isData => classification.isLayer('data');
  bool get _isPresentation => classification.isLayer('presentation');
  bool get _isInfrastructure => classification.isLayer('infrastructure');

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
    if (nativeStrict && (locatorTarget && locatorCall || topLevelLocatorCall)) {
      _report(
        DartitectRuleCodes.serviceLocator,
        'Service locator and lookup-by-type access are forbidden.',
        node.offset,
        '${target ?? ''}.$method',
      );
    }
    super.visitMethodInvocation(node);
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
    if (_isDomain && (uri.contains('/data/') || infrastructure)) {
      _report(
        DartitectRuleCodes.domainInfrastructure,
        'Domain code must not import data implementations or adapters.',
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

  void _report(String code, String message, int offset, String evidence) {
    final line = lineNumberAt(offset);
    if (isSuppressed(code, line)) return;
    addViolation(createViolation(code, message, path, line, evidence));
  }
}

Set<String> _parseLockPackages(List<String> lines) {
  final packages = <String>{};
  var inPackages = false;
  for (final line in lines) {
    if (line == 'packages:') {
      inPackages = true;
      continue;
    }
    if (!inPackages) continue;
    if (line.isNotEmpty && !line.startsWith(' ')) break;
    final match = RegExp(r'^  ([A-Za-z0-9_]+):\s*$').firstMatch(line);
    if (match != null) packages.add(match.group(1)!);
  }
  return packages;
}
