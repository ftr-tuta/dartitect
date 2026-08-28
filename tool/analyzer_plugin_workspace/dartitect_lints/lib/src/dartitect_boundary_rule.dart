import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'ecosystem_policy.g.dart';
import 'generated_boundary_policy.dart';
import 'lint_boundary_config.dart';

/// Parses standard file-level suppressions for Dartitect plugin diagnostics.
Set<String> dartitectIgnoredDiagnosticsForFile(String content) {
  final ignored = <String>{};
  final directives = RegExp(
    r'^\s*//\s*ignore_for_file:\s*([^\r\n]+)$',
    multiLine: true,
  ).allMatches(content);
  for (final directive in directives) {
    ignored.addAll(
      directive
          .group(1)!
          .split(',')
          .map((name) => name.trim().toLowerCase())
          .where((name) => name.startsWith('dartitect_')),
    );
  }
  return ignored;
}

/// Semantic counterparts of critical `dartitect scan` boundary rules.
final class DartitectBoundaryRule extends MultiAnalysisRule {
  /// Creates the combined rule set.
  DartitectBoundaryRule()
    : super(
        name: 'dartitect_architecture_boundaries',
        description: 'Enforces Native-First dependency direction.',
      );

  /// Domain importing Flutter.
  static const domainFlutterImport = LintCode(
    'dartitect_domain_flutter_import',
    'Domain code must not import Flutter.',
    correctionMessage:
        'Move the Flutter dependency to presentation or composition.',
    uniqueName: 'DartitectLint.domainFlutterImport',
  );

  /// Domain importing infrastructure.
  static const domainInfrastructureImport = LintCode(
    'dartitect_domain_infrastructure_import',
    'Domain/application code must not import data implementations or adapters.',
    correctionMessage: 'Depend on a pure-Dart contract instead.',
    uniqueName: 'DartitectLint.domainInfrastructureImport',
  );

  /// Data importing presentation.
  static const dataPresentationImport = LintCode(
    'dartitect_data_presentation_import',
    'Data code must not import presentation.',
    correctionMessage:
        'Invert the dependency through an application/domain contract.',
    uniqueName: 'DartitectLint.dataPresentationImport',
  );

  /// Presentation importing an infrastructure client.
  static const presentationInfrastructureImport = LintCode(
    'dartitect_presentation_infrastructure_import',
    'Presentation and ViewModels must not import infrastructure clients.',
    correctionMessage: 'Inject a repository or service contract.',
    uniqueName: 'DartitectLint.presentationInfrastructureImport',
  );

  /// BuildContext crossing into a non-widget boundary.
  static const buildContextBoundary = LintCode(
    'dartitect_build_context_boundary',
    'BuildContext must remain in widget/presentation boundaries.',
    correctionMessage: 'Pass data or a callback instead of BuildContext.',
    uniqueName: 'DartitectLint.buildContextBoundary',
  );

  /// Architecture/state framework import.
  static const forbiddenArchitectureImport = LintCode(
    'dartitect_forbidden_architecture_import',
    'This architecture or state framework is forbidden by the Native-First profile.',
    correctionMessage:
        'Use constructor injection and native Flutter listenables.',
    uniqueName: 'DartitectLint.forbiddenArchitectureImport',
  );

  /// Importing another package's private implementation.
  static const privateSrcImport = LintCode(
    'dartitect_private_src_import',
    'Private src/ imports from another package are forbidden.',
    correctionMessage: 'Import the package public entrypoint.',
    uniqueName: 'DartitectLint.privateSrcImport',
  );

  /// Concrete implementation imported outside composition/infrastructure.
  static const implementationBoundary = LintCode(
    'dartitect_implementation_boundary',
    'Concrete implementations may be imported only by infrastructure or composition.',
    correctionMessage: 'Inject a domain/application contract instead.',
    uniqueName: 'DartitectLint.implementationBoundary',
  );

  /// Provider type retained outside composition/infrastructure.
  static const providerTypeBoundary = LintCode(
    'dartitect_provider_type_boundary',
    'Provider types must remain in infrastructure or composition.',
    correctionMessage: 'Map to a consumer-owned contract or immutable model.',
    uniqueName: 'DartitectLint.providerTypeBoundary',
  );

  /// Flutter/router type retained outside View/composition.
  static const flutterTypeBoundary = LintCode(
    'dartitect_flutter_type_boundary',
    'Flutter Widget/router types must remain in View or composition.',
    correctionMessage: 'Pass data, an interface, or a callback.',
    uniqueName: 'DartitectLint.flutterTypeBoundary',
  );

  /// Forbidden architecture/state code generation.
  static const architectureCodegen = LintCode(
    'dartitect_architecture_codegen',
    'Architecture/state code generation is forbidden.',
    correctionMessage: 'Use explicit constructors and handwritten composition.',
    uniqueName: 'DartitectLint.architectureCodegen',
  );

  /// Provider codegen outside infrastructure.
  static const providerCodegenBoundary = LintCode(
    'dartitect_provider_codegen_boundary',
    'Provider code generation belongs in infrastructure.',
    correctionMessage: 'Move DTO/entity/schema declarations to infrastructure.',
    uniqueName: 'DartitectLint.providerCodegenBoundary',
  );

  /// Service locator or lookup-by-type usage.
  static const serviceLocator = LintCode(
    'dartitect_service_locator',
    'Service locator and lookup-by-type access are forbidden.',
    correctionMessage: 'Inject the typed dependency through a constructor.',
    uniqueName: 'DartitectLint.serviceLocator',
  );

  /// DartitectScope used as presentation service location.
  static const scopeBoundary = LintCode(
    'dartitect_scope_boundary',
    'DartitectScope may be used only by an explicit composition root.',
    correctionMessage:
        'Construct the ViewModel in composition and pass it to the View.',
    uniqueName: 'DartitectLint.scopeBoundary',
  );

  /// Direct console output bypassing the configured logger.
  static const directConsoleLogging = LintCode(
    'dartitect_direct_console_logging',
    'Direct console logging bypasses Dartitect redaction and routing.',
    correctionMessage: 'Inject DartitectLogger at the composition boundary.',
    uniqueName: 'DartitectLint.directConsoleLogging',
  );

  /// Vendor telemetry used outside an adapter/composition boundary.
  static const vendorObservabilityImport = LintCode(
    'dartitect_vendor_observability_import',
    'Vendor observability SDKs belong in an adapter or composition boundary.',
    correctionMessage: 'Depend on Dartitect observability interfaces instead.',
    uniqueName: 'DartitectLint.vendorObservabilityImport',
  );

  /// Empty catch clause that silently discards a failure.
  static const emptyCatch = LintCode(
    'dartitect_empty_catch',
    'An empty catch clause silently discards a failure.',
    correctionMessage: 'Handle, return a typed failure, or rethrow explicitly.',
    uniqueName: 'DartitectLint.emptyCatch',
  );

  /// Statically sensitive metadata key.
  static const sensitiveMetadataKey = LintCode(
    'dartitect_sensitive_metadata_key',
    'A statically sensitive key must not be placed in telemetry metadata.',
    correctionMessage: 'Remove the value or pass it through strict redaction.',
    uniqueName: 'DartitectLint.sensitiveMetadataKey',
  );

  /// Package prohibited by the versioned Native Strict ecosystem policy.
  static const ecosystemProhibited = LintCode(
    'dartitect_ecosystem_prohibited',
    'This dependency is prohibited by the Native Strict ecosystem policy.',
    correctionMessage: 'Use the Dartitect-owned replacement from the ledger.',
    uniqueName: 'DartitectLint.ecosystemProhibited',
  );

  /// Reviewed package used outside a valid scoped exception.
  static const ecosystemException = LintCode(
    'dartitect_ecosystem_exception',
    'This reviewed dependency requires a scoped, owned, non-expired exception.',
    correctionMessage:
        'Add or repair its entry in .dartitect/ecosystem-policy.json.',
    uniqueName: 'DartitectLint.ecosystemException',
  );

  /// Invalid boundary configuration that forced analyzer defaults.
  static const invalidConfiguration = LintCode(
    'dartitect_invalid_configuration',
    'dartitect.json is invalid; analyzer defaults are active only to continue diagnostics.',
    correctionMessage: 'Fix the stable-v1 configuration; run `dartitect doctor` for the exact field.',
    uniqueName: 'DartitectLint.invalidConfiguration',
  );

  /// Whether reviewed generated infrastructure may retain [uri].
  ///
  /// Provider generators may legitimately import their SDK internals and
  /// concrete model support. Architecture/state frameworks remain forbidden
  /// even when their imports were generated.
  static bool generatedInfrastructureAllowsImport(String uri) {
    final package = RegExp(r'^package:([^/]+)/').firstMatch(uri)?.group(1);
    return package == null ||
        !DartitectArchitectureRules.forbiddenPackages.contains(package);
  }

  @override
  List<DiagnosticCode> get diagnosticCodes => const <DiagnosticCode>[
    domainFlutterImport,
    domainInfrastructureImport,
    dataPresentationImport,
    presentationInfrastructureImport,
    buildContextBoundary,
    forbiddenArchitectureImport,
    privateSrcImport,
    implementationBoundary,
    providerTypeBoundary,
    flutterTypeBoundary,
    architectureCodegen,
    providerCodegenBoundary,
    serviceLocator,
    scopeBoundary,
    directConsoleLogging,
    vendorObservabilityImport,
    emptyCatch,
    sensitiveMetadataKey,
    ecosystemProhibited,
    ecosystemException,
    invalidConfiguration,
  ];

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    if (!context.isInLibDir || context.isInTestDirectory) return;
    final visitor = _BoundaryVisitor(this, context);
    registry
      ..addCompilationUnit(this, visitor)
      ..addImportDirective(this, visitor)
      ..addExportDirective(this, visitor)
      ..addNamedType(this, visitor)
      ..addAnnotation(this, visitor)
      ..addMethodInvocation(this, visitor)
      ..addCatchClause(this, visitor)
      ..addMapLiteralEntry(this, visitor);
  }
}

final class _BoundaryVisitor extends SimpleAstVisitor<void> {
  _BoundaryVisitor(this.rule, this.context);

  final DartitectBoundaryRule rule;
  final RuleContext context;

  late final Set<String> _ignoredForFile = dartitectIgnoredDiagnosticsForFile(
    (context.currentUnit ?? context.definingUnit).content,
  );

  String get _path => (context.currentUnit ?? context.definingUnit).file.path
      .replaceAll('\\', '/');

  bool get _generated => _classification.isGeneratedInfrastructure;

  bool get _isProviderPackage {
    final root = context.package?.root.path.replaceAll('\\', '/');
    if (root == null) return false;
    final package = root.split('/').where((part) => part.isNotEmpty).last;
    return DartitectArchitectureRules.infrastructurePackages.contains(package);
  }

  @override
  void visitCompilationUnit(CompilationUnit node) {
    if (_resolution.configurationError == null) return;
    _reportAtToken(node.beginToken, DartitectBoundaryRule.invalidConfiguration);
  }

  @override
  void visitImportDirective(ImportDirective node) {
    final importedSource =
        node.libraryImport?.importedLibrary?.firstFragment.source;
    final importsOwnPackage =
        importedSource != null &&
        (context.package?.contains(importedSource) ?? false);
    _inspectUri(node.uri, importsOwnPackage: importsOwnPackage);
    for (final configuration in node.configurations) {
      _inspectUri(configuration.uri, importsOwnPackage: false);
    }
  }

  @override
  void visitExportDirective(ExportDirective node) {
    _inspectUri(node.uri, importsOwnPackage: false);
    for (final configuration in node.configurations) {
      _inspectUri(configuration.uri, importsOwnPackage: false);
    }
  }

  @override
  void visitNamedType(NamedType node) {
    if (_generated) return;
    final typeName = node.name.lexeme;
    final classification = _classification;
    if (typeName == 'DartitectScope' &&
        _isFromPackages(node.element, const <String>{'dartitect_flutter'}) &&
        !classification.isCompositionRoot &&
        !_path.endsWith('/dartitect_scope.dart')) {
      _reportAtToken(node.name, DartitectBoundaryRule.scopeBoundary);
    }
    if (DartitectArchitectureRules.providerTypes.contains(typeName) &&
        _isFromPackages(
          node.element,
          DartitectArchitectureRules.infrastructurePackages,
        ) &&
        !_isProviderPackage &&
        !classification.isLayer('infrastructure') &&
        !classification.isCompositionRoot &&
        !_providerImportAlreadyReported) {
      _reportAtToken(node.name, DartitectBoundaryRule.providerTypeBoundary);
    }
    if (typeName != 'BuildContext' &&
        DartitectArchitectureRules.flutterBoundaryTypes.contains(typeName) &&
        _isFromPackages(node.element, const <String>{'flutter', 'go_router'}) &&
        !classification.isLayer('presentation') &&
        !classification.isCompositionRoot) {
      _reportAtToken(node.name, DartitectBoundaryRule.flutterTypeBoundary);
    }
    if (typeName != 'BuildContext') return;
    final libraryUri = node.element?.library?.uri.toString();
    if (libraryUri == null || !libraryUri.startsWith('package:flutter/'))
      return;
    final segments = _sourceSegments;
    final fileName = segments.last;
    final isViewModel =
        fileName.endsWith('_view_model.dart') || fileName.contains('viewmodel');
    final outsideWidgetBoundary =
        classification.isLayer('domain') ||
        classification.isLayer('data') ||
        isViewModel ||
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
    if (outsideWidgetBoundary) {
      _reportAtToken(node.name, DartitectBoundaryRule.buildContextBoundary);
    }
  }

  @override
  void visitAnnotation(Annotation node) {
    if (_generated) return;
    final name = node.name.toSource().split('.').last;
    if (DartitectArchitectureRules.architectureCodegenAnnotations.contains(
          name,
        ) &&
        _isFromPackages(
          node.element,
          DartitectArchitectureRules.forbiddenPackages,
        )) {
      _reportAtNode(node, DartitectBoundaryRule.architectureCodegen);
    }
    if (!_isProviderPackage &&
        !_classification.isLayer('infrastructure') &&
        DartitectArchitectureRules.providerCodegenAnnotations.contains(name) &&
        _isFromPackages(
          node.element,
          DartitectArchitectureRules.infrastructurePackages,
        )) {
      _reportAtNode(node, DartitectBoundaryRule.providerCodegenBoundary);
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_generated) return;
    final target = node.target?.toSource();
    final method = node.methodName.name;
    if (target == 'DartitectScope' &&
        _isFromPackages(node.methodName.element, const <String>{
          'dartitect_flutter',
        }) &&
        const <String>{'read', 'maybeRead'}.contains(method) &&
        !_classification.isCompositionRoot &&
        !_path.endsWith('/dartitect_scope.dart')) {
      _reportAtNode(node.methodName, DartitectBoundaryRule.scopeBoundary);
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
    if ((locatorTarget && locatorCall || topLevelLocatorCall) &&
        _isFromPackages(node.methodName.element, const <String>{
          'get_it',
          'watch_it',
          'injectable',
        })) {
      _reportAtNode(node.methodName, DartitectBoundaryRule.serviceLocator);
    }
    if (node.target == null && method == 'print') {
      final library = node.methodName.element?.library?.uri.toString();
      if (library != 'dart:core') return;
      _reportAtNode(
        node.methodName,
        DartitectBoundaryRule.directConsoleLogging,
      );
    }
  }

  @override
  void visitCatchClause(CatchClause node) {
    if (_generated || node.body.statements.isNotEmpty) return;
    _reportAtNode(node.body, DartitectBoundaryRule.emptyCatch);
  }

  @override
  void visitMapLiteralEntry(MapLiteralEntry node) {
    if (_generated || node.key is! StringLiteral) return;
    final key = (node.key as StringLiteral).stringValue?.toLowerCase();
    if (key == null ||
        !_sensitiveKeys.hasMatch(key) ||
        !_isTelemetryMetadata(node)) {
      return;
    }
    _reportAtNode(node.key, DartitectBoundaryRule.sensitiveMetadataKey);
  }

  bool _isTelemetryMetadata(MapLiteralEntry entry) {
    var cursor = entry.parent;
    for (var depth = 0; depth < 6 && cursor != null; depth += 1) {
      if (cursor is MethodInvocation) return _isTelemetrySink(cursor);
      if (cursor is! SetOrMapLiteral &&
          cursor is! ArgumentList &&
          cursor is! NamedArgument &&
          cursor is! ParenthesizedExpression) {
        return false;
      }
      cursor = cursor.parent;
    }
    return false;
  }

  bool _isTelemetrySink(MethodInvocation invocation) {
    const methods = <String>{
      'addBreadcrumb',
      'captureEvent',
      'captureException',
      'captureMessage',
      'log',
      'record',
      'report',
      'setContext',
      'setContexts',
      'setExtra',
    };
    if (!methods.contains(invocation.methodName.name)) return false;
    return _isFromPackages(
      invocation.methodName.element,
      const <String>{
        'dartitect_observability',
        'dartitect_sentry',
        'sentry',
        'sentry_flutter',
      },
      unresolvedTargets: const <String>{
        'DartitectLogger',
        'DartitectTelemetry',
        'Sentry',
      },
      target: invocation.target?.toSource(),
    );
  }

  void _inspectUri(StringLiteral literal, {required bool importsOwnPackage}) {
    final uri = literal.stringValue;
    if (uri == null) return;
    final package = RegExp(r'^package:([^/]+)/').firstMatch(uri)?.group(1);
    if (package != null) {
      final record = _ecosystemPolicy.explain(package, _path);
      switch (record.decision) {
        case DartitectEcosystemDecision.prohibitedNativeStrict:
        case DartitectEcosystemDecision.overlapWarning:
          _reportAtNode(literal, DartitectBoundaryRule.ecosystemProhibited);
        case DartitectEcosystemDecision.advisoryAlternative:
          if (_ecosystemPolicy.hasActiveConflict(package, _path)) {
            _reportAtNode(literal, DartitectBoundaryRule.ecosystemProhibited);
          }
        case DartitectEcosystemDecision.reviewedException:
          if (!_ecosystemPolicy.allowsExceptionAt(
            package,
            _path,
            DateTime.now().toUtc(),
          )) {
            _reportAtNode(literal, DartitectBoundaryRule.ecosystemException);
          }
        case DartitectEcosystemDecision.approved:
        case DartitectEcosystemDecision.approvedPrimitive:
        case DartitectEcosystemDecision.unreviewed:
          break;
      }
    }
    final classification = _classification;
    if (classification.isGeneratedInfrastructure) {
      if (!DartitectBoundaryRule.generatedInfrastructureAllowsImport(uri)) {
        _reportAtNode(
          literal,
          DartitectBoundaryRule.forbiddenArchitectureImport,
        );
      }
      return;
    }
    final segments = _sourceSegments;
    final fileName = segments.last;
    final isDomain = classification.isLayer('domain');
    final isApplication = classification.isLayer('application');
    final isData = classification.isLayer('data');
    final isPresentation =
        classification.isLayer('presentation') ||
        fileName.endsWith('_view_model.dart') ||
        fileName.contains('viewmodel');

    if (isDomain && uri.startsWith('package:flutter/')) {
      _reportAtNode(literal, DartitectBoundaryRule.domainFlutterImport);
    }
    if ((isDomain || isApplication) &&
        (uri.contains('/data/') ||
            package != null &&
                DartitectArchitectureRules.infrastructurePackages.contains(
                  package,
                ))) {
      _reportAtNode(literal, DartitectBoundaryRule.domainInfrastructureImport);
    }
    if (isData && uri.contains('/presentation/')) {
      _reportAtNode(literal, DartitectBoundaryRule.dataPresentationImport);
    }
    if (isPresentation &&
        package != null &&
        DartitectArchitectureRules.infrastructurePackages.contains(package) &&
        !classification.isCompositionRoot) {
      _reportAtNode(
        literal,
        DartitectBoundaryRule.presentationInfrastructureImport,
      );
      _providerImportAlreadyReported = true;
    }
    final importsImplementation =
        uri.contains('/infrastructure/') || uri.contains('/data/');
    final ownOrRelative =
        uri.startsWith('../') || uri.startsWith('./') || importsOwnPackage;
    if (importsImplementation &&
        ownOrRelative &&
        !classification.isLayer('infrastructure') &&
        !classification.isCompositionRoot &&
        !isDomain) {
      _reportAtNode(literal, DartitectBoundaryRule.implementationBoundary);
    }
    if (package != null &&
        DartitectArchitectureRules.forbiddenPackages.contains(package)) {
      _reportAtNode(literal, DartitectBoundaryRule.forbiddenArchitectureImport);
    }
    if (!importsOwnPackage && package != null && uri.contains('/src/')) {
      _reportAtNode(literal, DartitectBoundaryRule.privateSrcImport);
    }
    if (package != null &&
        const <String>{
          'sentry',
          'sentry_flutter',
          'sentry_dio',
        }.contains(package) &&
        !_isObservabilityBoundary) {
      _reportAtNode(literal, DartitectBoundaryRule.vendorObservabilityImport);
    }
  }

  bool _providerImportAlreadyReported = false;

  void _reportAtNode(AstNode node, DiagnosticCode diagnosticCode) {
    if (_ignoredForFile.contains(diagnosticCode.lowerCaseName)) return;
    rule.reportAtNode(node, diagnosticCode: diagnosticCode);
  }

  void _reportAtToken(Token token, DiagnosticCode diagnosticCode) {
    if (_ignoredForFile.contains(diagnosticCode.lowerCaseName)) return;
    rule.reportAtToken(token, diagnosticCode: diagnosticCode);
  }

  List<String> get _sourceSegments {
    final normalized = _path;
    final libIndex = normalized.lastIndexOf('/lib/');
    final source = libIndex < 0
        ? normalized
        : normalized.substring(libIndex + 5);
    return source.split('/').where((segment) => segment.isNotEmpty).toList();
  }

  late final DartitectLintBoundaryResolution _resolution =
      DartitectLintBoundaryResolver.resolve(
        _path,
        source: (context.currentUnit ?? context.definingUnit).content,
      );

  DartitectSourceClassification get _classification =>
      _resolution.classification;

  static const DartitectLintEcosystemPolicy _ecosystemPolicy =
      DartitectLintEcosystemPolicy();

  bool get _isObservabilityBoundary =>
      _path.contains('/dartitect_sentry/') ||
      _sourceSegments.any(
        const <String>{
          'adapter',
          'adapters',
          'composition',
          'infrastructure',
          'observability',
        }.contains,
      );

  static final _sensitiveKeys = RegExp(
    r'(^|[_-])(authorization|cookie|password|passwd|secret|token|api[_-]?key|dsn)($|[_-])',
    caseSensitive: false,
  );

  static bool _isFromPackages(
    Element? element,
    Set<String> packages, {
    Set<String> unresolvedTargets = const <String>{},
    String? target,
  }) {
    final uri = element?.library?.uri.toString();
    if (uri == null) {
      return unresolvedTargets.isEmpty ||
          target != null && unresolvedTargets.contains(target);
    }
    final package = RegExp(r'^package:([^/]+)/').firstMatch(uri)?.group(1);
    return package != null && packages.contains(package);
  }
}
