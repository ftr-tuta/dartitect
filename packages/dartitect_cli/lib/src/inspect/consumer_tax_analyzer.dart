import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// One AST- or element-backed consumer-tax observation.
final class ConsumerTaxSemanticFinding {
  /// Creates a source-free structural finding.
  const ConsumerTaxSemanticFinding({
    required this.code,
    required this.message,
    required this.evidence,
  });

  /// Stable consumer-tax diagnostic code.
  final String code;

  /// Remediation-oriented description.
  final String message;

  /// Bounded semantic evidence, never source bytes.
  final String evidence;
}

/// Semantic facts extracted from one Dart compilation unit.
final class ConsumerTaxFileFacts {
  /// Creates mutable facts while one unit is visited.
  ConsumerTaxFileFacts({required this.path, required this.test});

  /// Project-relative path.
  final String path;

  /// Whether this is consumer test/support code.
  final bool test;

  /// Whether resolved element identities were available.
  bool resolved = false;

  /// Imported package names.
  final Set<String> importedPackages = <String>{};

  /// Symbols resolved from Dartitect libraries.
  final Set<String> dartitectSymbols = <String>{};

  /// Semantic structural violations.
  final List<ConsumerTaxSemanticFinding> findings =
      <ConsumerTaxSemanticFinding>[];

  /// Listener-registration calls.
  int listeners = 0;

  /// Explicit lifecycle calls.
  int lifecycleCalls = 0;

  /// Consumer-created cancellation roots.
  int cancellationSources = 0;

  /// Direct low-level provider imports.
  int providerImports = 0;

  /// Structural graph plumbing observations.
  int architecturePlumbing = 0;

  /// Structural testing observations.
  int testTax = 0;
}

/// Shared Analyzer pass used by consumer-tax instead of source regexes.
final class ConsumerTaxSemanticAnalyzer {
  /// Creates an analyzer for one project boundary.
  ConsumerTaxSemanticAnalyzer(Directory root) : root = root.absolute;

  /// Project root.
  final Directory root;

  /// Parses every file and resolves element identities when package config is
  /// available. Syntactic AST mode remains deterministic when it is not.
  Future<List<ConsumerTaxFileFacts>> analyze(List<File> files) async {
    AnalysisContextCollection? collection;
    final packageConfig = File(
      '${root.path}${Platform.pathSeparator}.dart_tool'
      '${Platform.pathSeparator}package_config.json',
    );
    if (await packageConfig.exists()) {
      try {
        collection = AnalysisContextCollection(
          includedPaths: <String>[root.path],
          excludedPaths: <String>[
            '${root.path}${Platform.pathSeparator}.dart_tool',
            '${root.path}${Platform.pathSeparator}build',
          ],
        );
      } on Object {
        collection = null;
      }
    }
    final output = <ConsumerTaxFileFacts>[];
    try {
      for (final file in files) {
        final relative = file.path
            .substring(root.path.length + 1)
            .replaceAll(Platform.pathSeparator, '/');
        final facts = ConsumerTaxFileFacts(
          path: relative,
          test: relative.startsWith('test/'),
        );
        CompilationUnit? unit;
        if (collection != null) {
          try {
            final result = await collection
                .contextFor(file.path)
                .currentSession
                .getResolvedUnit(file.path);
            if (result is ResolvedUnitResult) {
              unit = result.unit;
              facts.resolved = true;
            }
          } on Object {
            // Older Analyzer floors may omit a valid generated unit from the
            // collection. Consumer-tax remains deterministic in AST mode and
            // reports the per-file fallback through its diagnostics.
            unit = null;
          }
        }
        unit ??= parseString(
          content: await file.readAsString(),
          path: file.path,
          throwIfDiagnostics: false,
        ).unit;
        unit.accept(_ConsumerTaxVisitor(facts));
        output.add(facts);
      }
    } finally {
      await collection?.dispose();
    }
    return output;
  }
}

final class _ConsumerTaxVisitor extends RecursiveAstVisitor<void> {
  _ConsumerTaxVisitor(this.facts);

  final ConsumerTaxFileFacts facts;
  var _importsDartitect = false;
  var _contextFactoryDepth = 0;
  final Set<String> _structuralMarkers = <String>{};

  @override
  void visitCompilationUnit(CompilationUnit node) {
    for (final directive in node.directives.whereType<ImportDirective>()) {
      final uri = directive.uri.stringValue;
      final package = uri == null
          ? null
          : RegExp(r'^package:([^/]+)/').firstMatch(uri)?.group(1);
      if (package == null) continue;
      facts.importedPackages.add(package);
      if (package.startsWith('dartitect')) _importsDartitect = true;
      if (const <String>{
        'dio',
        'drift',
        'objectbox',
        'workmanager',
      }.contains(package)) {
        facts.providerImports += 1;
      }
    }
    super.visitCompilationUnit(node);
    if (!facts.test && _structuralMarkers.length >= 2) {
      facts
        ..architecturePlumbing += 1
        ..findings.add(
          ConsumerTaxSemanticFinding(
            code: 'DT4004',
            message:
                'Pure assembly plumbing must be a managed generated output.',
            evidence: '${_structuralMarkers.length} resolved graph markers',
          ),
        );
    }
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final name = node.name;
    final library = node.element?.library?.uri.toString();
    if (facts.resolved && library?.startsWith('package:dartitect') == true) {
      if (_publicIdentifier.hasMatch(name)) facts.dartitectSymbols.add(name);
    } else if (!facts.resolved &&
        _importsDartitect &&
        _publicIdentifier.hasMatch(name) &&
        !_languageSymbols.contains(name)) {
      facts.dartitectSymbols.add(name);
    }
    if (_graphMarkers.contains(name) &&
        (library?.startsWith('package:dartitect') == true ||
            (!facts.resolved && _importsDartitect))) {
      _structuralMarkers.add(name);
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    final name = node.name.lexeme;
    final library = node.element?.library?.uri.toString();
    if (library?.startsWith('package:dartitect') == true ||
        (!facts.resolved && _importsDartitect)) {
      if (_publicIdentifier.hasMatch(name) &&
          !_languageSymbols.contains(name)) {
        facts.dartitectSymbols.add(name);
      }
      if (_graphMarkers.contains(name)) _structuralMarkers.add(name);
    }
    super.visitNamedType(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    final target = node.target?.toSource();
    if (!facts.resolved && _importsDartitect) {
      for (final identifier in <String?>[name, target]) {
        if (identifier != null && _publicIdentifier.hasMatch(identifier)) {
          facts.dartitectSymbols.add(identifier);
        }
      }
      if (!facts.test && _manualEngineTypes.contains(name) && target == null) {
        _addEngineFinding(name);
      }
      if (!facts.test &&
          _contextFactoryDepth == 0 &&
          _providerOwnerTypes.contains(target)) {
        _addOwnerFinding(target!);
      }
    }
    if (const <String>{
      'addListener',
      'removeListener',
      'listen',
    }.contains(name)) {
      facts.listeners += 1;
    }
    if (const <String>{
      'dispose',
      'disposeAsync',
      'close',
      'cancel',
    }.contains(name)) {
      facts.lifecycleCalls += 1;
    }
    if (facts.test &&
        const <String>{
          'readAsString',
          'readAsStringSync',
          'listSync',
        }.contains(name)) {
      facts
        ..testTax += 1
        ..findings.add(
          ConsumerTaxSemanticFinding(
            code: 'DT4010',
            message:
                'Architecture tests must use the generated semantic harness.',
            evidence: 'source-inspection method $name()',
          ),
        );
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final name = node.constructorName.type.name.lexeme;
    final library = node.constructorName.element?.library.uri.toString();
    final resolvedSdk = library?.startsWith('package:dartitect') == true;
    final syntacticSdk = !facts.resolved && _importsDartitect;
    if (resolvedSdk || syntacticSdk) facts.dartitectSymbols.add(name);
    if (!facts.test &&
        (resolvedSdk || syntacticSdk) &&
        _manualEngineTypes.contains(name)) {
      facts
        ..architecturePlumbing += 1
        ..findings.add(
          ConsumerTaxSemanticFinding(
            code: 'DT4003',
            message: 'SDK engine construction belongs in managed generated composition.',
            evidence: 'resolved constructor $name',
          ),
        );
    }
    if (!facts.test &&
        _contextFactoryDepth == 0 &&
        (resolvedSdk || syntacticSdk) &&
        _providerOwnerTypes.contains(name)) {
      facts
        ..architecturePlumbing += 1
        ..findings.add(
          ConsumerTaxSemanticFinding(
            code: 'DT4002',
            message: 'Provider owner plumbing belongs in managed generated composition.',
            evidence: 'resolved constructor $name',
          ),
        );
    }
    if (const <String>{'CancellationSource', 'CancelToken'}.contains(name)) {
      facts.cancellationSources += 1;
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitVariableDeclarationList(VariableDeclarationList node) {
    if (!facts.test && node.type?.toSource() == 'Object?') {
      for (final variable in node.variables) {
        if (!_capabilityNames.contains(variable.name.lexeme)) continue;
        facts
          ..architecturePlumbing += 1
          ..findings.add(
            ConsumerTaxSemanticFinding(
              code: 'DT4000',
              message: 'Capability slots in consumer composition must be concretely typed.',
              evidence: 'nullable slot ${variable.name.lexeme}',
            ),
          );
      }
    }
    super.visitVariableDeclarationList(node);
  }

  @override
  void visitNamedArgument(NamedArgument node) {
    if (!facts.test &&
        node.argumentExpression is NullLiteral &&
        _capabilityNames.contains(node.name.lexeme)) {
      facts
        ..architecturePlumbing += 1
        ..findings.add(
          ConsumerTaxSemanticFinding(
            code: 'DT4001',
            message:
                'Absent capabilities must not leave null composition slots.',
            evidence: 'null slot ${node.name.lexeme}',
          ),
        );
    }
    super.visitNamedArgument(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (facts.test && node.namePart.typeName.lexeme.startsWith('Fake')) {
      final interfaces =
          node.implementsClause?.interfaces
              .map((type) => type.name.lexeme)
              .where(_structuralFakeInterfaces.contains)
              .toList() ??
          const <String>[];
      if (interfaces.isNotEmpty) {
        facts
          ..testTax += 1
          ..findings.add(
            ConsumerTaxSemanticFinding(
              code: 'DT4011',
              message: 'Purely structural infrastructure fakes belong in the generated harness.',
              evidence: 'fake implements ${interfaces.join(',')}',
            ),
          );
      }
    }
    final contextFactory = node.metadata.any(
      (annotation) => _contextFactoryAnnotations.contains(annotation.name.name),
    );
    if (contextFactory) _contextFactoryDepth += 1;
    super.visitClassDeclaration(node);
    if (contextFactory) _contextFactoryDepth -= 1;
  }

  void _addEngineFinding(String name) {
    facts
      ..architecturePlumbing += 1
      ..findings.add(
        ConsumerTaxSemanticFinding(
          code: 'DT4003',
          message: 'SDK engine construction belongs in managed generated composition.',
          evidence: 'syntactic constructor $name',
        ),
      );
  }

  void _addOwnerFinding(String name) {
    facts
      ..architecturePlumbing += 1
      ..findings.add(
        ConsumerTaxSemanticFinding(
          code: 'DT4002',
          message: 'Provider owner plumbing belongs in managed generated composition.',
          evidence: 'syntactic constructor $name',
        ),
      );
  }
}

final _publicIdentifier = RegExp(r'^[A-Z][A-Za-z0-9_]*$');

const _languageSymbols = <String>{
  'Dart',
  'Future',
  'FutureOr',
  'List',
  'Map',
  'Object',
  'Set',
  'String',
};

const _capabilityNames = <String>{
  'repository',
  'storage',
  'transport',
  'scheduler',
  'observability',
  'sync',
  'outbox',
  'engine',
  'owner',
};

const _manualEngineTypes = <String>{
  'SyncEngine',
  'MutationCommand',
  'BootstrapCoordinator',
  'HeadlessSyncEndpoint',
};

const _providerOwnerTypes = <String>{
  'DioOwner',
  'DriftDatabaseOwner',
  'ObjectBoxStoreOwner',
};

const _contextFactoryAnnotations = <String>{
  'DartitectApplicationContextFactory',
  'DartitectSessionContextFactory',
  'DartitectTransportContextFactory',
};

const _graphMarkers = <String>{
  'DartitectAssemblyBinding',
  'OwnedGraph',
  'FeatureAssembly',
  'ApplicationModule',
  'SessionModule',
};

const _structuralFakeInterfaces = <String>{
  'MutationOutboxStore',
  'SyncCheckpointStore',
  'SyncLeaseStore',
  'SyncJournal',
  'SyncRemotePort',
  'DartitectScheduler',
  'DartitectTransport',
};
