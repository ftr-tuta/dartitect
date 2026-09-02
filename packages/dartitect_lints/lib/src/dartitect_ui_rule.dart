import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import 'dartitect_boundary_rule.dart';
import 'lint_boundary_config.dart';

/// Analyzer counterpart of `dartitect ui audit`.
final class DartitectUiRule extends MultiAnalysisRule {
  /// Creates the complete UI quality rule set.
  DartitectUiRule()
    : super(
        name: 'dartitect_ui_quality',
        description: 'Enforces business-neutral adaptive UI quality.',
      );

  /// DT3001: low-level custom Material button primitive.
  static const lowLevelMaterialControl = LintCode(
    'dartitect_dt3001',
    'Use an official Material button instead of a low-level custom-button primitive.',
    correctionMessage:
        'Prefer FilledButton, OutlinedButton, TextButton, or IconButton.',
    uniqueName: 'DartitectUiLint.dt3001',
    severity: DiagnosticSeverity.ERROR,
  );

  /// DT3002: orientation lock.
  static const orientationLock = LintCode(
    'dartitect_dt3002',
    'Application orientation locks conflict with the adaptive space contract.',
    correctionMessage:
        'Support resizable surfaces and select layout from available width.',
    uniqueName: 'DartitectUiLint.dt3002',
    severity: DiagnosticSeverity.ERROR,
  );

  /// DT3101: orientation-dependent layout.
  static const orientationBuilder = LintCode(
    'dartitect_dt3101',
    'OrientationBuilder makes layout depend on orientation rather than available space.',
    correctionMessage: 'Select a layout from finite available width.',
    uniqueName: 'DartitectUiLint.dt3101',
    severity: DiagnosticSeverity.WARNING,
  );

  /// DT3102: device/platform category used by presentation layout.
  static const devicePlatformSizing = LintCode(
    'dartitect_dt3102',
    'Presentation sizing appears to depend on a device or platform category.',
    correctionMessage: 'Use available constraints; reserve platform adaptation for established conventions.',
    uniqueName: 'DartitectUiLint.dt3102',
    severity: DiagnosticSeverity.WARNING,
  );

  /// DT3103: broad MediaQuery dependency.
  static const broadMediaQuery = LintCode(
    'dartitect_dt3103',
    'MediaQuery.of subscribes to every MediaQuery field.',
    correctionMessage: 'Use a focused accessor such as MediaQuery.sizeOf.',
    uniqueName: 'DartitectUiLint.dt3103',
    severity: DiagnosticSeverity.WARNING,
  );

  /// DT3104: gesture-backed action without evident semantics.
  static const gestureWithoutSemantics = LintCode(
    'dartitect_dt3104',
    'Gesture-backed control has no evident semantic wrapper or label.',
    correctionMessage: 'Prefer an official control or add explicit Semantics and keyboard behavior.',
    uniqueName: 'DartitectUiLint.dt3104',
    severity: DiagnosticSeverity.WARNING,
  );

  /// DT3105: visual literal outside a theme boundary.
  static const visualLiteral = LintCode(
    'dartitect_dt3105',
    'Visual color literal appears outside a consumer theme boundary.',
    correctionMessage: 'Move visual tokens into ThemeData, ColorScheme, a component theme, or ThemeExtension.',
    uniqueName: 'DartitectUiLint.dt3105',
    severity: DiagnosticSeverity.WARNING,
  );

  /// DT3106: unlabeled icon action.
  static const unlabeledIconAction = LintCode(
    'dartitect_dt3106',
    'Icon-only action has no observable tooltip or semantic label.',
    correctionMessage: 'Provide a localized tooltip or semantic label.',
    uniqueName: 'DartitectUiLint.dt3106',
    severity: DiagnosticSeverity.WARNING,
  );

  /// DT3120: presentation imports an infrastructure library.
  static const presentationInfrastructureImport = LintCode(
    'dartitect_dt3120',
    'Presentation must not import infrastructure libraries.',
    correctionMessage: 'Inject a provider-neutral repository contract.',
    uniqueName: 'DartitectUiLint.dt3120',
    severity: DiagnosticSeverity.ERROR,
  );

  /// DT3121: presentation directly retains an infrastructure type.
  static const infrastructureTypeAccess = LintCode(
    'dartitect_dt3121',
    'Presentation must not access an infrastructure type directly.',
    correctionMessage:
        'Project the value through a domain or application contract.',
    uniqueName: 'DartitectUiLint.dt3121',
    severity: DiagnosticSeverity.ERROR,
  );

  /// DT3122: a reusable widget receives a session or composition root.
  static const reusableWidgetRoot = LintCode(
    'dartitect_dt3122',
    'Reusable widgets must receive values and callbacks, not a session or composition root.',
    correctionMessage:
        'Project immutable view data and pure callbacks at the route boundary.',
    uniqueName: 'DartitectUiLint.dt3122',
    severity: DiagnosticSeverity.ERROR,
  );

  /// DT3123: a widget initiates infrastructure or native I/O.
  static const widgetIo = LintCode(
    'dartitect_dt3123',
    'Widgets must not initiate infrastructure, native, or network I/O.',
    correctionMessage: 'Move I/O behind a ViewModel command and repository.',
    uniqueName: 'DartitectUiLint.dt3123',
    severity: DiagnosticSeverity.ERROR,
  );

  /// DT3124: Dartitect state is wrapped by another observable owner.
  static const wrappedDartitectState = LintCode(
    'dartitect_dt3124',
    'Dartitect state must not be wrapped in another observable state owner.',
    correctionMessage: 'Observe the existing Dartitect owner directly.',
    uniqueName: 'DartitectUiLint.dt3124',
    severity: DiagnosticSeverity.ERROR,
  );

  /// DT3125: a domain object is mutated inside setState.
  static const domainMutationInSetState = LintCode(
    'dartitect_dt3125',
    'setState must not perform a domain mutation.',
    correctionMessage:
        'Invoke a ViewModel command and render its published state.',
    uniqueName: 'DartitectUiLint.dt3125',
    severity: DiagnosticSeverity.ERROR,
  );

  /// DT3126: an owned resource is created by build.
  static const resourceCreatedInBuild = LintCode(
    'dartitect_dt3126',
    'build must not create a controller, subscription, or owned resource.',
    correctionMessage: 'Create the resource in lifecycle setup and dispose it deterministically.',
    uniqueName: 'DartitectUiLint.dt3126',
    severity: DiagnosticSeverity.ERROR,
  );

  /// DT3127: a retained resource has no matching cleanup.
  static const missingResourceCleanup = LintCode(
    'dartitect_dt3127',
    'A retained controller, subscription, or resource has no matching cleanup.',
    correctionMessage:
        'Dispose, cancel, or close the resource from the owning lifecycle.',
    uniqueName: 'DartitectUiLint.dt3127',
    severity: DiagnosticSeverity.ERROR,
  );

  /// DT3128: BuildContext is used after await without a mounted guard.
  static const contextAfterAwait = LintCode(
    'dartitect_dt3128',
    'BuildContext is used after await without a mounted guard.',
    correctionMessage:
        'Guard with mounted or context.mounted before using the context.',
    uniqueName: 'DartitectUiLint.dt3128',
    severity: DiagnosticSeverity.ERROR,
  );

  /// DT3130: invalid Flutter preview function signature.
  static const invalidPreviewSignature = LintCode(
    'dartitect_dt3130',
    'Flutter previews must be synchronous top-level zero-argument Widget functions.',
    correctionMessage: 'Return a Widget synchronously from a zero-argument top-level function.',
    uniqueName: 'DartitectUiLint.dt3130',
    severity: DiagnosticSeverity.ERROR,
  );

  /// DT3131: preview declared outside the dev-only source boundary.
  static const previewLocation = LintCode(
    'dartitect_dt3131',
    'Flutter previews must live under lib/src/dev/.',
    correctionMessage:
        'Move the preview and its synthetic fixtures to lib/src/dev/.',
    uniqueName: 'DartitectUiLint.dt3131',
    severity: DiagnosticSeverity.ERROR,
  );

  /// DT3132: preview reaches runtime or I/O work.
  static const previewRuntimeReachability = LintCode(
    'dartitect_dt3132',
    'Flutter preview code reaches native I/O, an adapter, network work, or global initialization.',
    correctionMessage:
        'Use immutable synthetic fixtures and pure callbacks only.',
    uniqueName: 'DartitectUiLint.dt3132',
    severity: DiagnosticSeverity.ERROR,
  );

  /// DT3140: eager collection materialization in presentation.
  static const eagerUiCollection = LintCode(
    'dartitect_dt3140',
    'Presentation eagerly materializes a collection that should remain lazy.',
    correctionMessage: 'Use a lazy builder or indexed projection.',
    uniqueName: 'DartitectUiLint.dt3140',
    severity: DiagnosticSeverity.ERROR,
  );

  /// DT3141: dynamic list nested in SingleChildScrollView.
  static const dynamicListInSingleChildScrollView = LintCode(
    'dartitect_dt3141',
    'A dynamic list must not be nested in SingleChildScrollView.',
    correctionMessage: 'Use one lazy sliver or list as the scroll owner.',
    uniqueName: 'DartitectUiLint.dt3141',
    severity: DiagnosticSeverity.ERROR,
  );

  /// DT3142: static subtree rebuilt by a listenable builder.
  static const staticSubtreeRebuilt = LintCode(
    'dartitect_dt3142',
    'A static subtree is rebuilt by a listenable builder.',
    correctionMessage: 'Hoist the subtree into the builder child or make it const outside the callback.',
    uniqueName: 'DartitectUiLint.dt3142',
    severity: DiagnosticSeverity.ERROR,
  );

  /// DT3143: heavy synchronous work in build.
  static const heavyBuildWork = LintCode(
    'dartitect_dt3143',
    'build performs heavy synchronous work.',
    correctionMessage:
        'Precompute in the ViewModel, isolate, or lifecycle boundary.',
    uniqueName: 'DartitectUiLint.dt3143',
    severity: DiagnosticSeverity.ERROR,
  );

  /// DT3144: image lacks finite layout constraints.
  static const unconstrainedImage = LintCode(
    'dartitect_dt3144',
    'Image rendering has no evident finite width or height constraint.',
    correctionMessage:
        'Provide width/height or wrap the image in a finite constraint.',
    uniqueName: 'DartitectUiLint.dt3144',
    severity: DiagnosticSeverity.ERROR,
  );

  /// DT3145: incompatible nested scroll owners.
  static const incompatibleNestedScroll = LintCode(
    'dartitect_dt3145',
    'Nested scrollables compete for the same scroll axis.',
    correctionMessage:
        'Use one scroll owner or disable inner scrolling explicitly.',
    uniqueName: 'DartitectUiLint.dt3145',
    severity: DiagnosticSeverity.ERROR,
  );

  @override
  List<DiagnosticCode> get diagnosticCodes => const <DiagnosticCode>[
    lowLevelMaterialControl,
    orientationLock,
    orientationBuilder,
    devicePlatformSizing,
    broadMediaQuery,
    gestureWithoutSemantics,
    visualLiteral,
    unlabeledIconAction,
    presentationInfrastructureImport,
    infrastructureTypeAccess,
    reusableWidgetRoot,
    widgetIo,
    wrappedDartitectState,
    domainMutationInSetState,
    resourceCreatedInBuild,
    missingResourceCleanup,
    contextAfterAwait,
    invalidPreviewSignature,
    previewLocation,
    previewRuntimeReachability,
    eagerUiCollection,
    dynamicListInSingleChildScrollView,
    staticSubtreeRebuilt,
    heavyBuildWork,
    unconstrainedImage,
    incompatibleNestedScroll,
  ];

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    if (!context.isInLibDir || context.isInTestDirectory) return;
    final visitor = _UiVisitor(this, context);
    registry
      ..addCompilationUnit(this, visitor)
      ..addImportDirective(this, visitor)
      ..addClassDeclaration(this, visitor)
      ..addFunctionDeclaration(this, visitor)
      ..addInstanceCreationExpression(this, visitor)
      ..addMethodInvocation(this, visitor)
      ..addPrefixedIdentifier(this, visitor)
      ..addSimpleIdentifier(this, visitor)
      ..addNamedType(this, visitor);
  }
}

final class _UiVisitor extends SimpleAstVisitor<void> {
  _UiVisitor(this.rule, this.context);

  final DartitectUiRule rule;
  final RuleContext context;

  late final String _source =
      (context.currentUnit ?? context.definingUnit).content;
  late final Set<String> _ignored = dartitectIgnoredDiagnosticsForFile(_source);
  late final DartitectLintBoundaryResolution _resolution =
      DartitectLintBoundaryResolver.resolve(_path, source: _source);
  final Set<String> _reportedStableCodes = <String>{};

  String get _path => (context.currentUnit ?? context.definingUnit).file.path
      .replaceAll('\\', '/');

  bool get _themeBoundary {
    final segments = _path.toLowerCase().split('/');
    final file = segments.last;
    return segments.contains('theme') ||
        segments.contains('themes') ||
        file.contains('theme');
  }

  bool get _flutterPresentationLibrary =>
      (context.currentUnit ?? context.definingUnit).unit.directives.any(
        (directive) => RegExp(
          r'''(?:import|export)\s+['"]package:flutter/(?:material|widgets|cupertino)\.dart['"]''',
        ).hasMatch(directive.toSource()),
      );

  bool get _presentationBoundary =>
      _resolution.classification.isLayer('presentation');

  bool get _dartitectFlutterImplementation {
    final packageRoot = context.package?.root.path.replaceAll('\\', '/');
    return (packageRoot?.endsWith('/dartitect_flutter') ?? false) ||
        _path.contains('/packages/dartitect_flutter/lib/');
  }

  @override
  void visitImportDirective(ImportDirective node) {
    if (!_presentationBoundary) return;
    final library = node.libraryImport?.importedLibrary;
    if (library != null && _isInfrastructureUri(library.uri.toString())) {
      _report(node, DartitectUiRule.presentationInfrastructureImport, 'DT3120');
    }
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (!_isWidgetOwner(node)) return;
    final dispose = node.body.members
        .whereType<MethodDeclaration>()
        .where((method) => method.name.lexeme == 'dispose')
        .map((method) => method.body.toSource())
        .join('\n');
    for (final field in node.body.members.whereType<FieldDeclaration>()) {
      for (final variable in field.fields.variables) {
        final initializer = variable.initializer;
        if (initializer == null || !_isOwnedResource(initializer)) continue;
        final name = variable.name.lexeme;
        if (RegExp(
          '\\b${RegExp.escape(name)}\\s*\\.\\s*(?:dispose|cancel|close)\\s*\\(',
        ).hasMatch(dispose)) {
          continue;
        }
        _report(variable, DartitectUiRule.missingResourceCleanup, 'DT3127');
      }
    }
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (!_hasPreviewAnnotation(node.metadata)) return;
    final element = node.declaredFragment?.element;
    final parameters = node.functionExpression.parameters?.parameters;
    final validReturn = _isSubtype(
      element?.returnType,
      package: 'flutter',
      name: 'Widget',
    );
    if (parameters == null ||
        parameters.isNotEmpty ||
        node.functionExpression.body.isAsynchronous ||
        !validReturn) {
      _report(node, DartitectUiRule.invalidPreviewSignature, 'DT3130');
    }
    if (!_path.contains('/lib/src/dev/')) {
      _report(node, DartitectUiRule.previewLocation, 'DT3131');
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type.name.lexeme;
    final element = node.constructorName.element;
    if (type == 'RawMaterialButton' && _isFlutter(element, 'material.dart')) {
      _report(node, DartitectUiRule.lowLevelMaterialControl, 'DT3001');
    } else if (type == 'OrientationBuilder' &&
        _isFlutter(element, 'widgets.dart')) {
      _report(node, DartitectUiRule.orientationBuilder, 'DT3101');
    } else if (_flutterPresentationLibrary &&
        _isSizingDecision(node) &&
        type == 'DeviceInfoPlugin' &&
        _isFromPackages(element, const <String>{'device_info_plus'})) {
      _report(node, DartitectUiRule.devicePlatformSizing, 'DT3102');
    } else if (type == 'GestureDetector' &&
        _isFlutter(element, 'widgets.dart') &&
        _hasGestureAction(node) &&
        !_hasEvidentSemantics(node)) {
      _report(node, DartitectUiRule.gestureWithoutSemantics, 'DT3104');
    } else if (type == 'IconButton' &&
        _isFlutter(element, 'material.dart') &&
        !_hasIconActionLabel(node)) {
      _report(node, DartitectUiRule.unlabeledIconAction, 'DT3106');
    } else if (!_themeBoundary &&
        !_insideThemeConstruction(node) &&
        type == 'Color' &&
        element?.library.uri.toString() == 'dart:ui') {
      _report(node, DartitectUiRule.visualLiteral, 'DT3105');
    }
    if (_insideBuild(node) && _isOwnedResource(node)) {
      _report(node, DartitectUiRule.resourceCreatedInBuild, 'DT3126');
    }
    if (_isObservableOwner(node.staticType) &&
        _containsDartitectState(node.staticType)) {
      _report(node, DartitectUiRule.wrappedDartitectState, 'DT3124');
    }
    if (_presentationBoundary &&
        _insideWidgetOwner(node) &&
        _isDangerousElement(element)) {
      _report(node, DartitectUiRule.widgetIo, 'DT3123');
    }
    if (_insidePreview(node) && _isDangerousElement(element)) {
      _report(node, DartitectUiRule.previewRuntimeReachability, 'DT3132');
    }
    if (_insideBuild(node) &&
        _isSubtype(node.staticType, library: 'dart:core', name: 'RegExp')) {
      _report(node, DartitectUiRule.heavyBuildWork, 'DT3143');
    }
    if (_insideBuild(node) &&
        _isFlutterWidgetType(node.staticType, const <String>{
          'AnimatedBuilder',
          'ListenableBuilder',
          'ValueListenableBuilder',
        }) &&
        _hasStaticBuilderWithoutChild(node)) {
      _report(node, DartitectUiRule.staticSubtreeRebuilt, 'DT3142');
    }
    if (_insideBuild(node) &&
        _isFlutterWidgetType(node.staticType, const <String>{
          'SingleChildScrollView',
        }) &&
        _containsDynamicList(node)) {
      _report(
        node,
        DartitectUiRule.dynamicListInSingleChildScrollView,
        'DT3141',
      );
    }
    if (_insideBuild(node) &&
        _isFlutterWidgetType(node.staticType, const <String>{'Image'}) &&
        !_hasFiniteImageConstraint(node)) {
      _report(node, DartitectUiRule.unconstrainedImage, 'DT3144');
    }
    if (_insideBuild(node) &&
        _isScrollable(node) &&
        _hasIncompatibleScrollableAncestor(node)) {
      _report(node, DartitectUiRule.incompatibleNestedScroll, 'DT3145');
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target?.toSource();
    final method = node.methodName.name;
    if (target == 'SystemChrome' &&
        method == 'setPreferredOrientations' &&
        _isFlutter(node.methodName.element, 'services.dart')) {
      _report(node, DartitectUiRule.orientationLock, 'DT3002');
    } else if (target == 'MediaQuery' &&
        method == 'of' &&
        _isFlutter(node.methodName.element, 'widgets.dart')) {
      _report(node, DartitectUiRule.broadMediaQuery, 'DT3103');
    }
    if (_presentationBoundary &&
        _insideWidgetOwner(node) &&
        _isDangerousElement(node.methodName.element)) {
      _report(node, DartitectUiRule.widgetIo, 'DT3123');
    }
    if (_insidePreview(node) && _isDangerousElement(node.methodName.element)) {
      _report(node, DartitectUiRule.previewRuntimeReachability, 'DT3132');
    }
    if (_insideBuild(node) &&
        node.methodName.name == 'listen' &&
        _isOwnedResource(node)) {
      _report(node, DartitectUiRule.resourceCreatedInBuild, 'DT3126');
    }
    if (_insideBuild(node) &&
        node.methodName.name == 'toList' &&
        node.target is MethodInvocation &&
        const <String>{
          'expand',
          'map',
          'where',
        }.contains((node.target! as MethodInvocation).methodName.name)) {
      _report(node, DartitectUiRule.eagerUiCollection, 'DT3140');
    }
    if (_insideBuild(node) && _isHeavyBuildInvocation(node)) {
      _report(node, DartitectUiRule.heavyBuildWork, 'DT3143');
    }
    if (_isDomainMutation(node) && _insideSetStateCallback(node)) {
      _report(node, DartitectUiRule.domainMutationInSetState, 'DT3125');
    }
  }

  @override
  void visitNamedType(NamedType node) {
    final element = node.element;
    if (_presentationBoundary && _isInfrastructureElement(element)) {
      _report(node, DartitectUiRule.infrastructureTypeAccess, 'DT3121');
    }
    final owner = _enclosingClass(node);
    if (_presentationBoundary &&
        !_dartitectFlutterImplementation &&
        owner != null &&
        _isWidgetOwner(owner) &&
        _isSessionOrRootType(node.type)) {
      _report(node, DartitectUiRule.reusableWidgetRoot, 'DT3122');
    }
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    final packageUri = node.identifier.element?.library?.uri.toString();
    if (_flutterPresentationLibrary &&
        _isSizingDecision(node) &&
        node.prefix.name == 'Platform' &&
        packageUri == 'dart:io' &&
        const <String>{
          'isAndroid',
          'isIOS',
          'isLinux',
          'isMacOS',
          'isWindows',
          'isFuchsia',
        }.contains(node.identifier.name)) {
      _report(node, DartitectUiRule.devicePlatformSizing, 'DT3102');
    }
    if (!_themeBoundary &&
        !_insideThemeConstruction(node) &&
        node.prefix.name == 'Colors' &&
        _isFlutter(node.identifier.element, 'material.dart')) {
      _report(node, DartitectUiRule.visualLiteral, 'DT3105');
    }
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (_flutterPresentationLibrary &&
        _isSizingDecision(node) &&
        (node.name == 'defaultTargetPlatform' || node.name == 'kIsWeb') &&
        _isFlutter(node.element, 'foundation.dart')) {
      _report(node, DartitectUiRule.devicePlatformSizing, 'DT3102');
    }
    if (node.name == 'context' &&
        _isSubtype(
          _identifierType(node),
          package: 'flutter',
          name: 'BuildContext',
        ) &&
        !_isMountedAccess(node) &&
        _isContextUseAfterAwait(node) &&
        !_hasMountedGuard(node)) {
      _report(node, DartitectUiRule.contextAfterAwait, 'DT3128');
    }
  }

  DartType? _identifierType(SimpleIdentifier node) {
    final element = node.element;
    return element is VariableElement ? element.type : node.staticType;
  }

  bool _isMountedAccess(SimpleIdentifier node) => switch (node.parent) {
    PrefixedIdentifier(:final prefix, :final identifier) =>
      identical(prefix, node) && identifier.name == 'mounted',
    PropertyAccess(:final target, :final propertyName) =>
      identical(target, node) && propertyName.name == 'mounted',
    _ => false,
  };

  ClassDeclaration? _enclosingClass(AstNode node) {
    var cursor = node.parent;
    while (cursor != null) {
      if (cursor is ClassDeclaration) return cursor;
      cursor = cursor.parent;
    }
    return null;
  }

  FunctionBody? _enclosingFunctionBody(AstNode node) {
    var cursor = node.parent;
    while (cursor != null) {
      if (cursor is FunctionBody) return cursor;
      cursor = cursor.parent;
    }
    return null;
  }

  bool _insideBuild(AstNode node) {
    var cursor = node.parent;
    while (cursor != null) {
      if (cursor is MethodDeclaration) {
        final owner = _enclosingClass(cursor);
        return cursor.name.lexeme == 'build' &&
            owner != null &&
            _isWidgetOwner(owner);
      }
      if (cursor is FunctionDeclaration) return false;
      cursor = cursor.parent;
    }
    return false;
  }

  bool _insideWidgetOwner(AstNode node) {
    final owner = _enclosingClass(node);
    return owner != null && _isWidgetOwner(owner);
  }

  bool _isWidgetOwner(ClassDeclaration declaration) {
    final type = declaration.declaredFragment?.element.thisType;
    return _isSubtype(type, package: 'flutter', name: 'Widget') ||
        _isSubtype(type, package: 'flutter', name: 'State');
  }

  bool _insidePreview(AstNode node) {
    var cursor = node.parent;
    while (cursor != null) {
      if (cursor is FunctionDeclaration) {
        return _hasPreviewAnnotation(cursor.metadata);
      }
      cursor = cursor.parent;
    }
    return false;
  }

  bool _hasPreviewAnnotation(NodeList<Annotation> metadata) => metadata.any((
    annotation,
  ) {
    final uri = annotation.element?.library?.uri.toString();
    final name = annotation.name.toSource().split('.').last;
    return name == 'DartitectPreviewMatrix' &&
            (uri?.startsWith('package:dartitect_flutter_testing/') ?? false) ||
        name == 'Preview' && uri == 'package:flutter/widget_previews.dart';
  });

  bool _isOwnedResource(AstNode node) {
    final type = switch (node) {
      Expression(:final staticType) => staticType,
      _ => null,
    };
    if (type is! InterfaceType) return false;
    final interfaces = <InterfaceType>[type, ...type.allSupertypes];
    return interfaces.any((candidate) {
      final uri = candidate.element.library.uri.toString();
      final name = candidate.element.name;
      if (uri == 'dart:async' && name == 'StreamSubscription') return true;
      if (uri.startsWith('package:flutter/') &&
          const <String>{
            'AnimationController',
            'FocusNode',
            'ScrollController',
            'TabController',
            'TextEditingController',
          }.contains(name)) {
        return true;
      }
      if (uri.startsWith('package:dartitect_flutter/') &&
          const <String>{
            'DartitectObservableResource',
            'DartitectViewModel',
            'ReactiveSourceSession',
          }.contains(name)) {
        return true;
      }
      return false;
    });
  }

  bool _isObservableOwner(DartType? type) {
    if (type is! InterfaceType) return false;
    return <InterfaceType>[type, ...type.allSupertypes].any((candidate) {
      final uri = candidate.element.library.uri.toString();
      return uri == 'package:flutter/foundation.dart' &&
              const <String>{
                'ChangeNotifier',
                'ValueNotifier',
              }.contains(candidate.element.name) ||
          const <String>{
            'provider',
            'riverpod',
            'flutter_riverpod',
          }.contains(_packageName(uri));
    });
  }

  bool _containsDartitectState(DartType? type) {
    if (type is! ParameterizedType) return false;
    for (final argument in type.typeArguments) {
      if (argument is InterfaceType) {
        final uri = argument.element.library.uri.toString();
        if (uri.startsWith('package:dartitect_flutter/') &&
            const <String>{
              'CommandState',
              'DartitectViewModel',
              'ResourceSnapshot',
              'SessionState',
            }.contains(argument.element.name)) {
          return true;
        }
      }
      if (_containsDartitectState(argument)) return true;
    }
    return false;
  }

  bool _isSessionOrRootType(DartType? type) {
    if (type is! InterfaceType) return false;
    return <InterfaceType>[type, ...type.allSupertypes].any((candidate) {
      final uri = candidate.element.library.uri.toString();
      return (uri.startsWith('package:dartitect_flutter/') ||
              uri.startsWith('package:dartitect/')) &&
          const <String>{
            'ApplicationHost',
            'BootstrapCoordinator',
            'DartitectScope',
            'SessionRuntimeController',
            'SessionStateController',
          }.contains(candidate.element.name);
    });
  }

  bool _isInfrastructureElement(Element? element) {
    final uri = element?.library?.uri.toString();
    return uri != null && _isInfrastructureUri(uri);
  }

  bool _isInfrastructureUri(String uri) {
    final normalized = uri.toLowerCase();
    if (normalized == 'dart:io' || normalized == 'dart:ffi') return true;
    if (const <String>{
      'dio',
      'drift',
      'firebase_core',
      'http',
      'objectbox',
      'path_provider',
      'shared_preferences',
      'sqflite',
    }.contains(_packageName(normalized))) {
      return true;
    }
    return RegExp(
      r'/(?:adapter|adapters|infrastructure|remote|services?|stores?)/',
    ).hasMatch(normalized);
  }

  bool _isDangerousElement(Element? element) {
    final uri = element?.library?.uri.toString();
    if (uri == null) return false;
    return _isInfrastructureUri(uri) ||
        const <String>{'dart:ffi', 'dart:io', 'dart:isolate'}.contains(uri);
  }

  bool _isDomainMutation(MethodInvocation node) {
    if (!const <String>{
      'add',
      'clear',
      'complete',
      'delete',
      'remove',
      'save',
      'set',
      'toggle',
      'update',
    }.contains(node.methodName.name)) {
      return false;
    }
    final uri = node.methodName.element?.library?.uri.toString();
    return uri != null &&
        RegExp(r'/(?:application|domain)/').hasMatch(uri.toLowerCase());
  }

  bool _insideSetStateCallback(AstNode node) {
    var cursor = node.parent;
    while (cursor != null) {
      if (cursor is MethodInvocation &&
          cursor.methodName.name == 'setState' &&
          _isFlutter(cursor.methodName.element, 'widgets.dart')) {
        return true;
      }
      if (cursor is MethodDeclaration || cursor is FunctionDeclaration) {
        return false;
      }
      cursor = cursor.parent;
    }
    return false;
  }

  bool _isHeavyBuildInvocation(MethodInvocation node) {
    final uri = node.methodName.element?.library?.uri.toString();
    if (uri == 'dart:convert' &&
        const <String>{
          'base64Decode',
          'jsonDecode',
          'jsonEncode',
          'utf8.decode',
        }.contains(node.methodName.name)) {
      return true;
    }
    return uri == 'dart:core' && node.methodName.name == 'sort';
  }

  bool _hasStaticBuilderWithoutChild(InstanceCreationExpression node) {
    if (_arguments(node).any((argument) => argument.name.lexeme == 'child')) {
      return false;
    }
    final builder = _arguments(node)
        .where((argument) => argument.name.lexeme == 'builder')
        .map((argument) => argument.argumentExpression)
        .whereType<FunctionExpression>()
        .firstOrNull;
    if (builder == null) return false;
    final returned = switch (builder.body) {
      ExpressionFunctionBody(:final expression) => expression,
      BlockFunctionBody(:final block)
          when block.statements.length == 1 &&
              block.statements.single is ReturnStatement =>
        (block.statements.single as ReturnStatement).expression,
      _ => null,
    };
    if (returned == null ||
        !_isSubtype(returned.staticType, package: 'flutter', name: 'Widget')) {
      return false;
    }
    final body = builder.body.toSource();
    final names = builder.parameters?.parameters
        .map((parameter) => parameter.name?.lexeme)
        .whereType<String>();
    if (names != null &&
        names.any(
          (name) => RegExp('\\b${RegExp.escape(name)}\\b').hasMatch(body),
        )) {
      return false;
    }
    return !RegExp(r'\b(?:this|widget)\.').hasMatch(body);
  }

  bool _containsDynamicList(InstanceCreationExpression node) {
    final visitor = _DynamicListVisitor(_isFlutterWidgetType);
    node.argumentList.accept(visitor);
    return visitor.found;
  }

  bool _hasFiniteImageConstraint(InstanceCreationExpression node) {
    if (_arguments(node).any(
      (argument) =>
          const <String>{'height', 'width'}.contains(argument.name.lexeme),
    )) {
      return true;
    }
    var cursor = node.parent;
    for (var depth = 0; depth < 4 && cursor != null; depth += 1) {
      if (cursor is InstanceCreationExpression &&
          _isFlutterWidgetType(cursor.staticType, const <String>{
            'AspectRatio',
            'ConstrainedBox',
            'LimitedBox',
            'SizedBox',
          })) {
        return true;
      }
      cursor = cursor.parent;
    }
    return false;
  }

  bool _isScrollable(InstanceCreationExpression node) =>
      _isFlutterWidgetType(node.staticType, const <String>{
        'CustomScrollView',
        'GridView',
        'ListView',
        'PageView',
        'SingleChildScrollView',
      });

  bool _hasIncompatibleScrollableAncestor(InstanceCreationExpression node) {
    if (_isInnerScrollDisabled(node)) return false;
    final axis = _scrollAxis(node);
    var cursor = node.parent;
    while (cursor != null) {
      if (cursor is InstanceCreationExpression && _isScrollable(cursor)) {
        if (_isFlutterWidgetType(cursor.staticType, const <String>{
          'SingleChildScrollView',
        })) {
          return false;
        }
        return axis == _scrollAxis(cursor);
      }
      cursor = cursor.parent;
    }
    return false;
  }

  bool _isInnerScrollDisabled(InstanceCreationExpression node) {
    final source = node.argumentList.toSource();
    return RegExp(
          r'physics\s*:\s*(?:const\s+)?NeverScrollableScrollPhysics\s*\(',
        ).hasMatch(source) &&
        RegExp(r'shrinkWrap\s*:\s*true\b').hasMatch(source);
  }

  String _scrollAxis(InstanceCreationExpression node) =>
      RegExp(r'scrollDirection\s*:\s*Axis\.horizontal\b')
          .hasMatch(node.argumentList.toSource())
      ? 'horizontal'
      : 'vertical';

  bool _isContextUseAfterAwait(SimpleIdentifier node) {
    final body = _enclosingFunctionBody(node);
    if (body == null) return false;
    final visitor = _AwaitOffsetVisitor(node.offset);
    body.accept(visitor);
    return visitor.latestEnd != null;
  }

  bool _hasMountedGuard(SimpleIdentifier node) {
    final body = _enclosingFunctionBody(node);
    if (body == null) return false;
    final visitor = _AwaitOffsetVisitor(node.offset);
    body.accept(visitor);
    final awaitEnd = visitor.latestEnd;
    if (awaitEnd == null || awaitEnd > node.offset) return false;
    final between = _source.substring(awaitEnd, node.offset);
    return RegExp(
      r'if\s*\(\s*!\s*(?:context\s*\.\s*)?mounted\s*\)\s*(?:return\b|\{[^}]*\breturn\b)',
      dotAll: true,
    ).hasMatch(between);
  }

  bool _isFlutterWidgetType(DartType? type, Set<String> names) {
    if (type is! InterfaceType) return false;
    return names.contains(type.element.name) &&
        type.element.library.uri.toString().startsWith('package:flutter/');
  }

  bool _isSubtype(
    DartType? type, {
    String? package,
    String? library,
    required String name,
  }) {
    if (type is! InterfaceType) return false;
    return <InterfaceType>[type, ...type.allSupertypes].any((candidate) {
      if (candidate.element.name != name) return false;
      final uri = candidate.element.library.uri.toString();
      if (library != null) return uri == library;
      return package != null && uri.startsWith('package:$package/');
    });
  }

  static String? _packageName(String uri) =>
      RegExp(r'^package:([^/]+)/').firstMatch(uri)?.group(1);

  bool _hasGestureAction(InstanceCreationExpression node) => _arguments(node)
      .any(
        (argument) => const <String>{
          'onTap',
          'onLongPress',
          'onDoubleTap',
          'onSecondaryTap',
        }.contains(argument.name.lexeme),
      );

  bool _hasEvidentSemantics(InstanceCreationExpression node) {
    var cursor = node.parent;
    for (var depth = 0; depth < 5 && cursor != null; depth += 1) {
      if (cursor is InstanceCreationExpression &&
          cursor.constructorName.type.name.lexeme == 'Semantics') {
        return _semanticsHasLabel(cursor);
      }
      cursor = cursor.parent;
    }
    return _arguments(node).any((argument) {
      if (argument.name.lexeme != 'child') return false;
      final expression = argument.argumentExpression;
      return expression is InstanceCreationExpression &&
          expression.constructorName.type.name.lexeme == 'Semantics' &&
          _semanticsHasLabel(expression);
    });
  }

  bool _semanticsHasLabel(InstanceCreationExpression node) => _arguments(node)
      .any(
        (argument) => const <String>{
          'label',
          'button',
          'link',
          'textField',
        }.contains(argument.name.lexeme),
      );

  bool _hasIconActionLabel(InstanceCreationExpression node) {
    if (_arguments(node).any((argument) => argument.name.lexeme == 'tooltip')) {
      return true;
    }
    final icon = _arguments(node)
        .where((argument) => argument.name.lexeme == 'icon')
        .map((argument) => argument.argumentExpression)
        .whereType<InstanceCreationExpression>()
        .firstOrNull;
    return icon != null &&
            _arguments(icon)
                .any((argument) => argument.name.lexeme == 'semanticLabel') ||
        _hasEvidentSemantics(node);
  }

  Iterable<NamedArgument> _arguments(InstanceCreationExpression node) =>
      node.argumentList.arguments.whereType<NamedArgument>();

  bool _isSizingDecision(AstNode node) {
    AstNode? cursor = node;
    for (var depth = 0; depth < 8 && cursor != null; depth += 1) {
      if (cursor is VariableDeclaration || cursor is Statement) {
        final source = cursor.toSource().toLowerCase();
        return RegExp(
          r'width|height|size|layout|compact|medium|expanded|breakpoint|padding|extent',
        ).hasMatch(source);
      }
      cursor = cursor.parent;
    }
    return false;
  }

  bool _insideThemeConstruction(AstNode node) {
    var cursor = node.parent;
    for (var depth = 0; depth < 8 && cursor != null; depth += 1) {
      if (cursor is InstanceCreationExpression &&
          const <String>{
            'ThemeData',
            'ColorScheme',
            'ThemeExtension',
          }.contains(cursor.constructorName.type.name.lexeme)) {
        return true;
      }
      cursor = cursor.parent;
    }
    return false;
  }

  void _report(AstNode node, DiagnosticCode diagnostic, String stableCode) {
    if (_ignored.contains(diagnostic.lowerCaseName) ||
        _resolution.suppressedCodes.contains(stableCode) ||
        !_reportedStableCodes.add(stableCode)) {
      return;
    }
    rule.reportAtNode(node, diagnosticCode: diagnostic);
  }

  static bool _isFlutter(Element? element, String library) =>
      element?.library?.uri.toString() == 'package:flutter/$library';

  static bool _isFromPackages(Element? element, Set<String> packages) {
    final uri = element?.library?.uri.toString();
    final package = uri == null
        ? null
        : RegExp(r'^package:([^/]+)/').firstMatch(uri)?.group(1);
    return package != null && packages.contains(package);
  }
}

final class _DynamicListVisitor extends RecursiveAstVisitor<void> {
  _DynamicListVisitor(this.isFlutterWidgetType);

  final bool Function(DartType?, Set<String>) isFlutterWidgetType;
  bool found = false;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (isFlutterWidgetType(node.staticType, const <String>{
      'GridView',
      'ListView',
    })) {
      found = true;
      return;
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (const <String>{
      'expand',
      'map',
      'toList',
    }.contains(node.methodName.name)) {
      found = true;
      return;
    }
    super.visitMethodInvocation(node);
  }
}

final class _AwaitOffsetVisitor extends RecursiveAstVisitor<void> {
  _AwaitOffsetVisitor(this.beforeOffset);

  final int beforeOffset;
  int? latestEnd;

  @override
  void visitAwaitExpression(AwaitExpression node) {
    if (node.end < beforeOffset &&
        (latestEnd == null || node.end > latestEnd!)) {
      latestEnd = node.end;
    }
    super.visitAwaitExpression(node);
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
