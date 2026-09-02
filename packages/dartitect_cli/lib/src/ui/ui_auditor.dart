import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import '../config/dartitect_config.dart';
import '../diagnostics/models.dart';
import '../rules/generated_boundary_policy.dart';

/// Stable UI audit diagnostic codes shared with the analyzer plugin.
abstract final class DartitectUiAuditCodes {
  /// Direct use of a low-level Material custom-button primitive.
  static const lowLevelMaterialControl = 'DT3001';

  /// Application orientation lock.
  static const orientationLock = 'DT3002';

  /// Layout selected from orientation instead of available space.
  static const orientationBuilder = 'DT3101';

  /// Layout selected from a device or platform category.
  static const devicePlatformSizing = 'DT3102';

  /// Broad MediaQuery dependency.
  static const broadMediaQuery = 'DT3103';

  /// Gesture-backed control without evident semantics.
  static const gestureWithoutSemantics = 'DT3104';

  /// Visual literal outside a consumer theme boundary.
  static const visualLiteral = 'DT3105';

  /// Icon-only action without an observable label.
  static const unlabeledIconAction = 'DT3106';
}

/// Read-only, deterministic UI quality audit for Flutter presentation source.
final class DartitectUiAuditor {
  /// Creates an auditor rooted at one Dart or Flutter project.
  DartitectUiAuditor(Directory root) : root = root.absolute;

  /// Absolute root used only for IO. Reports contain relative paths.
  final Directory root;

  /// Audits source and returns the standard command envelope.
  Future<CommandEnvelope> audit({bool strict = false}) async {
    final configFile = File(_join(root.path, 'dartitect.json'));
    final config = await configFile.exists()
        ? await DartitectConfig.load(configFile)
        : null;
    final classifier = config == null
        ? DartitectBoundaryClassifier.defaults()
        : DartitectBoundaryClassifier(
            layers: config.layers,
            compositionRoots: config.compositionRoots,
            generatedInfrastructure: config.generatedInfrastructure,
            generatedSuffixes: config.generatedSuffixes,
          );
    final pubspec = File(_join(root.path, 'pubspec.yaml'));
    final packageName = await pubspec.exists()
        ? RegExp(
            r'^name:\s*([^\s#]+)',
            multiLine: true,
          ).firstMatch(await pubspec.readAsString())?.group(1)
        : null;
    final files = await _dartFiles();
    final warnings = <DartitectFinding>[];
    final errors = <DartitectFinding>[];
    final now = DateTime.now().toUtc();
    for (final file in files) {
      final path = _relative(file.path);
      final source = await file.readAsString();
      final parsed = parseString(
        content: source,
        path: file.path,
        throwIfDiagnostics: false,
      );
      final visitor = _UiAuditVisitor(
        path: path,
        source: source,
        themeBoundary: _isThemeBoundary(path),
        presentationBoundary: classifier
            .classify(path, source: source)
            .isLayer('presentation'),
        flutterPresentationLibrary: parsed.unit.directives.any(
          (directive) => RegExp(
            r'''(?:import|export)\s+['"]package:flutter/(?:material|widgets|cupertino)\.dart['"]''',
          ).hasMatch(directive.toSource()),
        ),
        localTypes: parsed.unit.declarations
            .whereType<ClassDeclaration>()
            .map((declaration) => declaration.namePart.typeName.lexeme)
            .toSet(),
        dartitectFlutterImplementation:
            packageName == 'dartitect_flutter' ||
            path.startsWith('packages/dartitect_flutter/'),
        lineAt: (offset) => parsed.lineInfo.getLocation(offset),
        isSuppressed: (code) =>
            config?.suppressions.any(
              (suppression) =>
                  suppression.code == code &&
                  !suppression.isExpiredAt(now) &&
                  dartitectGlobMatches(suppression.path, path),
            ) ??
            false,
        onFinding: (finding) {
          if (finding.severity == FindingSeverity.error) {
            errors.add(finding);
          } else {
            warnings.add(finding);
          }
        },
      );
      parsed.unit.accept(visitor);
    }
    warnings.sort(_compareFinding);
    errors.sort(_compareFinding);
    return CommandEnvelope(
      command: 'ui-audit',
      project: <String, Object?>{
        'root': '.',
        'dartFiles': files.length,
        'strict': strict,
      },
      findings: List<DartitectFinding>.unmodifiable(warnings),
      violations: List<DartitectFinding>.unmodifiable(errors),
      exitCode: errors.isNotEmpty || strict && warnings.isNotEmpty ? 1 : 0,
    );
  }

  Future<List<File>> _dartFiles() async {
    final output = <File>[];
    Future<void> walk(Directory directory) async {
      final relative = _relative(directory.path);
      if (relative.split('/').any(_ignoredDirectoryNames.contains)) return;
      final entities = await directory.list(followLinks: false).toList()
        ..sort((left, right) => left.path.compareTo(right.path));
      for (final entity in entities) {
        if (entity is Directory) {
          await walk(entity);
        } else if (entity is File &&
            entity.path.endsWith('.dart') &&
            _isAuditedLibraryPath(_relative(entity.path))) {
          output.add(entity);
        }
      }
    }

    await walk(root);
    output.sort((left, right) => left.path.compareTo(right.path));
    return output;
  }

  String _relative(String path) {
    final relative = path.substring(root.path.length).replaceAll('\\', '/');
    return relative.startsWith('/') ? relative.substring(1) : relative;
  }

  static bool _isAuditedLibraryPath(String path) =>
      !path.startsWith('tool/analyzer_plugin_fixture/') &&
      (path.startsWith('lib/') || path.contains('/lib/'));

  static bool _isThemeBoundary(String path) {
    final segments = path.toLowerCase().split('/');
    final file = segments.last;
    return segments.contains('theme') ||
        segments.contains('themes') ||
        file.contains('theme');
  }

  static const _ignoredDirectoryNames = <String>{
    '.dart_tool',
    '.git',
    '.private',
    '.symlinks',
    'build',
    'ephemeral',
    'pods',
  };

  static int _compareFinding(DartitectFinding left, DartitectFinding right) {
    final path = (left.path ?? '').compareTo(right.path ?? '');
    if (path != 0) return path;
    final line = (left.line ?? 0).compareTo(right.line ?? 0);
    if (line != 0) return line;
    return left.code.compareTo(right.code);
  }

  static String _join(String left, String right) =>
      '$left${Platform.pathSeparator}${right.replaceAll('/', Platform.pathSeparator)}';
}

final class _UiAuditVisitor extends RecursiveAstVisitor<void> {
  _UiAuditVisitor({
    required this.path,
    required this.source,
    required this.themeBoundary,
    required this.presentationBoundary,
    required this.flutterPresentationLibrary,
    required this.localTypes,
    required this.dartitectFlutterImplementation,
    required this.lineAt,
    required this.isSuppressed,
    required this.onFinding,
  });

  final String path;
  final String source;
  final bool themeBoundary;
  final bool presentationBoundary;
  final bool flutterPresentationLibrary;
  final Set<String> localTypes;
  final bool dartitectFlutterImplementation;
  final CharacterLocation Function(int offset) lineAt;
  final bool Function(String code) isSuppressed;
  final void Function(DartitectFinding finding) onFinding;
  final Set<String> _reportedCodes = <String>{};

  @override
  void visitImportDirective(ImportDirective node) {
    final uri = node.uri.stringValue?.toLowerCase();
    if (presentationBoundary &&
        uri != null &&
        _looksLikeInfrastructureUri(uri)) {
      _reportQuality(
        node,
        'DT3120',
        'Presentation appears to import an infrastructure library.',
        'Inject a provider-neutral repository contract.',
      );
    }
    super.visitImportDirective(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (!_isWidgetOwner(node)) {
      super.visitClassDeclaration(node);
      return;
    }
    final dispose = node.body.members
        .whereType<MethodDeclaration>()
        .where((method) => method.name.lexeme == 'dispose')
        .map((method) => method.body.toSource())
        .join('\n');
    for (final field in node.body.members.whereType<FieldDeclaration>()) {
      for (final variable in field.fields.variables) {
        final initializer = variable.initializer;
        if (initializer == null || !_looksLikeOwnedResource(initializer))
          continue;
        final name = variable.name.lexeme;
        if (RegExp(
          '\\b${RegExp.escape(name)}\\s*\\.\\s*(?:dispose|cancel|close)\\s*\\(',
        ).hasMatch(dispose)) {
          continue;
        }
        _reportQuality(
          variable,
          'DT3127',
          'A retained resource has no evident matching cleanup.',
          'Dispose, cancel, or close it from the owning lifecycle.',
        );
      }
    }
    super.visitClassDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (_hasPreviewAnnotation(node.metadata)) {
      final parameters = node.functionExpression.parameters?.parameters;
      final returnType = node.returnType?.toSource();
      if (parameters == null ||
          parameters.isNotEmpty ||
          node.functionExpression.body.isAsynchronous ||
          returnType == null ||
          !RegExp(r'(?:^|\.)Widget\??$').hasMatch(returnType)) {
        _reportQuality(
          node,
          'DT3130',
          'Preview signature appears invalid.',
          'Return a Widget synchronously from a zero-argument top-level function.',
        );
      }
      if (!path.contains('/lib/src/dev/') && !path.startsWith('lib/src/dev/')) {
        _reportQuality(
          node,
          'DT3131',
          'Preview is outside the allowed dev-only source boundary.',
          'Move it under lib/src/dev/.',
        );
      }
    }
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type.name.lexeme;
    _visitWidgetCall(type, node.argumentList, node);
    if (_insideBuild(node) && _looksLikeOwnedResource(node)) {
      _reportQuality(
        node,
        'DT3126',
        'build appears to create an owned resource.',
        'Create it in lifecycle setup and dispose it deterministically.',
      );
    }
    if (!localTypes.contains(type) &&
        RegExp(r'^(?:ChangeNotifier|ValueNotifier)$').hasMatch(type) &&
        RegExp(r'<[^>]*(?:CommandState|ResourceSnapshot|SessionState)[^>]*>')
            .hasMatch(node.constructorName.type.toSource())) {
      _reportQuality(
        node,
        'DT3124',
        'Dartitect state appears wrapped in another observable owner.',
        'Observe the existing Dartitect owner directly.',
      );
    }
    if (presentationBoundary &&
        !dartitectFlutterImplementation &&
        _insideWidgetOwner(node) &&
        !localTypes.contains(type) &&
        _looksLikeDangerousCall(type, null)) {
      _reportQuality(
        node,
        'DT3123',
        'A widget appears to initiate infrastructure, native, or network I/O.',
        'Move I/O behind a ViewModel command and repository.',
      );
    }
    if (_insidePreview(node) &&
        !localTypes.contains(type) &&
        _looksLikeDangerousCall(type, null)) {
      _reportQuality(
        node,
        'DT3132',
        'Preview code appears to reach runtime or I/O work.',
        'Use immutable synthetic fixtures and pure callbacks only.',
      );
    }
    if (_insideBuild(node) && !localTypes.contains(type) && type == 'RegExp') {
      _reportQuality(
        node,
        'DT3143',
        'build appears to perform heavy synchronous work.',
        'Precompute outside presentation build.',
      );
    }
    if (_insideBuild(node) &&
        !localTypes.contains(type) &&
        const <String>{
          'AnimatedBuilder',
          'ListenableBuilder',
          'ValueListenableBuilder',
        }.contains(type) &&
        _hasStaticBuilderWithoutChild(node.argumentList)) {
      _reportQuality(
        node,
        'DT3142',
        'A static subtree appears to be rebuilt by a listenable builder.',
        'Hoist it into child or outside the callback.',
      );
    }
    if (_insideBuild(node) &&
        !localTypes.contains(type) &&
        type == 'SingleChildScrollView' &&
        RegExp(r'\b(?:GridView|ListView)\s*(?:\.|\()')
            .hasMatch(node.argumentList.toSource())) {
      _reportQuality(
        node,
        'DT3141',
        'A dynamic list appears nested in SingleChildScrollView.',
        'Use one lazy scroll owner.',
      );
    }
    if (_insideBuild(node) &&
        !localTypes.contains(type) &&
        type == 'Image' &&
        !_hasFiniteImageConstraint(node)) {
      _reportQuality(
        node,
        'DT3144',
        'Image has no evident finite constraints.',
        'Provide width/height or a finite constraint wrapper.',
      );
    }
    if (_insideBuild(node) &&
        !localTypes.contains(type) &&
        _scrollableTypes.contains(type) &&
        _hasIncompatibleScrollableAncestor(node)) {
      _reportQuality(
        node,
        'DT3145',
        'Nested scrollables appear to compete for one axis.',
        'Use one scroll owner or disable the inner scroll explicitly.',
      );
    }
    super.visitInstanceCreationExpression(node);
  }

  void _visitWidgetCall(String type, ArgumentList arguments, AstNode node) {
    if (type == 'RawMaterialButton') {
      _report(
        node,
        DartitectUiAuditCodes.lowLevelMaterialControl,
        FindingSeverity.error,
        'Use an official Material button instead of a low-level custom-button primitive.',
        'Prefer FilledButton, FilledButton.tonal, OutlinedButton, TextButton, or IconButton.',
      );
    } else if (type == 'OrientationBuilder') {
      _report(
        node,
        DartitectUiAuditCodes.orientationBuilder,
        FindingSeverity.warning,
        'OrientationBuilder makes layout depend on orientation rather than available space.',
        'Use DartitectResponsiveWindowBuilder or DartitectResponsiveRegionBuilder.',
      );
    } else if (flutterPresentationLibrary &&
        _isSizingDecision(node) &&
        type == 'DeviceInfoPlugin') {
      _reportDeviceSizing(node);
    } else if (type == 'GestureDetector' && _hasGestureAction(arguments)) {
      if (!_hasEvidentSemantics(node, arguments)) {
        _report(
          node,
          DartitectUiAuditCodes.gestureWithoutSemantics,
          FindingSeverity.warning,
          'Gesture-backed control has no evident semantic wrapper or label.',
          'Prefer an official control or add explicit Semantics and keyboard behavior.',
        );
      }
    } else if (type == 'IconButton' && !_hasIconActionLabel(node, arguments)) {
      _report(
        node,
        DartitectUiAuditCodes.unlabeledIconAction,
        FindingSeverity.warning,
        'Icon-only action has no observable tooltip or semantic label.',
        'Provide a localized tooltip or semantic label.',
      );
    } else if (!themeBoundary &&
        !_insideThemeConstruction(node) &&
        type == 'Color') {
      _reportVisualLiteral(node);
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target?.toSource();
    final method = node.methodName.name;
    if (target == 'SystemChrome' && method == 'setPreferredOrientations') {
      _report(
        node,
        DartitectUiAuditCodes.orientationLock,
        FindingSeverity.error,
        'Application orientation locks conflict with the adaptive space contract.',
        'Support resizable surfaces and select layout from available width.',
      );
    } else if (target == 'MediaQuery' && method == 'of') {
      _report(
        node,
        DartitectUiAuditCodes.broadMediaQuery,
        FindingSeverity.warning,
        'MediaQuery.of subscribes to every MediaQuery field.',
        'Use a focused accessor such as MediaQuery.sizeOf or MediaQuery.textScalerOf.',
      );
    } else if (target == null) {
      // Unresolved parsing represents constructor-shaped calls without
      // `new` or `const` as method invocations. Audit both AST forms so the
      // standalone CLI stays deterministic without a package resolution step.
      _visitWidgetCall(method, node.argumentList, node);
    }
    final unresolvedConstruction = target == null
        ? method
        : const <String>{'GridView', 'Image', 'ListView'}.contains(target)
        ? target
        : null;
    if (unresolvedConstruction != null) {
      _visitUnresolvedConstructionQuality(
        unresolvedConstruction,
        node.argumentList,
        node,
      );
    }
    if (presentationBoundary &&
        !dartitectFlutterImplementation &&
        _insideWidgetOwner(node) &&
        _looksLikeDangerousCall(target, method)) {
      _reportQuality(
        node,
        'DT3123',
        'A widget appears to initiate infrastructure, native, or network I/O.',
        'Move I/O behind a ViewModel command and repository.',
      );
    }
    if (_insidePreview(node) && _looksLikeDangerousCall(target, method)) {
      _reportQuality(
        node,
        'DT3132',
        'Preview code appears to reach runtime or I/O work.',
        'Use immutable synthetic fixtures and pure callbacks only.',
      );
    }
    if (_insideBuild(node) && method == 'listen') {
      _reportQuality(
        node,
        'DT3126',
        'build appears to create a subscription.',
        'Subscribe in lifecycle setup and cancel deterministically.',
      );
    }
    if (_insideBuild(node) &&
        method == 'toList' &&
        node.target is MethodInvocation &&
        const <String>{
          'expand',
          'map',
          'where',
        }.contains((node.target! as MethodInvocation).methodName.name)) {
      _reportQuality(
        node,
        'DT3140',
        'Presentation appears to materialize a collection eagerly.',
        'Use a lazy builder or indexed projection.',
      );
    }
    if (_insideBuild(node) &&
        const <String>{
          'base64Decode',
          'jsonDecode',
          'jsonEncode',
          'sort',
        }.contains(method)) {
      _reportQuality(
        node,
        'DT3143',
        'build appears to perform heavy synchronous work.',
        'Precompute outside presentation build.',
      );
    }
    if (_insideSetStateCallback(node) &&
        const <String>{
          'add',
          'clear',
          'complete',
          'delete',
          'remove',
          'save',
          'set',
          'toggle',
          'update',
        }.contains(method)) {
      _reportQuality(
        node,
        'DT3125',
        'setState appears to perform a domain mutation.',
        'Invoke a ViewModel command instead.',
      );
    }
    super.visitMethodInvocation(node);
  }

  void _visitUnresolvedConstructionQuality(
    String type,
    ArgumentList arguments,
    AstNode node,
  ) {
    if (localTypes.contains(type)) return;
    if (_insideBuild(node) &&
        const <String>{
          'AnimationController',
          'FocusNode',
          'ScrollController',
          'StreamSubscription',
          'TabController',
          'TextEditingController',
        }.contains(type)) {
      _reportQuality(
        node,
        'DT3126',
        'build appears to create an owned resource.',
        'Create it in lifecycle setup and dispose it deterministically.',
      );
    }
    if (RegExp(r'^(?:ChangeNotifier|ValueNotifier)$').hasMatch(type) &&
        RegExp(r'<[^>]*(?:CommandState|ResourceSnapshot|SessionState)[^>]*>')
            .hasMatch(node.toSource())) {
      _reportQuality(
        node,
        'DT3124',
        'Dartitect state appears wrapped in another observable owner.',
        'Observe the existing Dartitect owner directly.',
      );
    }
    if (_insideBuild(node) &&
        const <String>{
          'AnimatedBuilder',
          'ListenableBuilder',
          'ValueListenableBuilder',
        }.contains(type) &&
        _hasStaticBuilderWithoutChild(arguments)) {
      _reportQuality(
        node,
        'DT3142',
        'A static subtree appears to be rebuilt by a listenable builder.',
        'Hoist it into child or outside the callback.',
      );
    }
    if (_insideBuild(node) &&
        type == 'SingleChildScrollView' &&
        RegExp(r'\b(?:GridView|ListView)\s*(?:\.|\()')
            .hasMatch(arguments.toSource())) {
      _reportQuality(
        node,
        'DT3141',
        'A dynamic list appears nested in SingleChildScrollView.',
        'Use one lazy scroll owner.',
      );
    }
    if (_insideBuild(node) &&
        type == 'Image' &&
        !_hasFiniteConstraint(node, arguments)) {
      _reportQuality(
        node,
        'DT3144',
        'Image has no evident finite constraints.',
        'Provide width/height or a finite constraint wrapper.',
      );
    }
    if (_insideBuild(node) &&
        _scrollableTypes.contains(type) &&
        _hasIncompatibleScrollableAncestorCall(node, arguments)) {
      _reportQuality(
        node,
        'DT3145',
        'Nested scrollables appear to compete for one axis.',
        'Use one scroll owner or disable the inner scroll explicitly.',
      );
    }
  }

  @override
  void visitNamedType(NamedType node) {
    final type = node.name.lexeme;
    if (presentationBoundary &&
        !localTypes.contains(type) &&
        RegExp(
          r'(?:Adapter|Backend|Client|Database|NativeTaskStore|RemoteService|Store)$',
        ).hasMatch(type)) {
      _reportQuality(
        node,
        'DT3121',
        'Presentation appears to access an infrastructure type directly.',
        'Project it through a domain or application contract.',
      );
    }
    if (presentationBoundary &&
        !dartitectFlutterImplementation &&
        _insideWidgetOwner(node) &&
        const <String>{
          'ApplicationHost',
          'BootstrapCoordinator',
          'DartitectScope',
          'SessionRuntimeController',
          'SessionStateController',
        }.contains(type)) {
      _reportQuality(
        node,
        'DT3122',
        'A reusable widget appears to receive a session or composition root.',
        'Pass immutable values and callbacks instead.',
      );
    }
    super.visitNamedType(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (flutterPresentationLibrary &&
        _isSizingDecision(node) &&
        node.prefix.name == 'Platform' &&
        const <String>{
          'isAndroid',
          'isIOS',
          'isLinux',
          'isMacOS',
          'isWindows',
          'isFuchsia',
        }.contains(node.identifier.name)) {
      _reportDeviceSizing(node);
    }
    if (!themeBoundary &&
        !_insideThemeConstruction(node) &&
        node.prefix.name == 'Colors') {
      _reportVisualLiteral(node);
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (flutterPresentationLibrary &&
        _isSizingDecision(node) &&
        (node.name == 'defaultTargetPlatform' || node.name == 'kIsWeb')) {
      _reportDeviceSizing(node);
    }
    if (node.name == 'context' &&
        _hasBuildContextParameter(node) &&
        !_isMountedAccess(node) &&
        _isContextUseAfterAwait(node) &&
        !_hasMountedGuard(node)) {
      _reportQuality(
        node,
        'DT3128',
        'BuildContext appears to be used after await without a mounted guard.',
        'Guard with mounted or context.mounted first.',
      );
    }
    super.visitSimpleIdentifier(node);
  }

  void _reportDeviceSizing(AstNode node) {
    _report(
      node,
      DartitectUiAuditCodes.devicePlatformSizing,
      FindingSeverity.warning,
      'Presentation sizing appears to depend on a device or platform category.',
      'Use available constraints; reserve platform adaptation for established conventions.',
    );
  }

  void _reportVisualLiteral(AstNode node) {
    _report(
      node,
      DartitectUiAuditCodes.visualLiteral,
      FindingSeverity.warning,
      'Visual color literal appears outside a consumer theme boundary.',
      'Move visual tokens into ThemeData, ColorScheme, a component theme, or ThemeExtension.',
    );
  }

  bool _hasGestureAction(ArgumentList arguments) => _arguments(arguments).any(
    (argument) => const <String>{
      'onTap',
      'onLongPress',
      'onDoubleTap',
      'onSecondaryTap',
    }.contains(argument.name.lexeme),
  );

  bool _hasEvidentSemantics(AstNode node, ArgumentList arguments) {
    var cursor = node.parent;
    for (var depth = 0; depth < 5 && cursor != null; depth += 1) {
      if (_callName(cursor) == 'Semantics') {
        return _semanticsHasLabel(cursor);
      }
      cursor = cursor.parent;
    }
    return _arguments(arguments).any((argument) {
      if (argument.name.lexeme != 'child') return false;
      final expression = argument.argumentExpression;
      return _callName(expression) == 'Semantics' &&
          _semanticsHasLabel(expression);
    });
  }

  bool _semanticsHasLabel(AstNode node) => _argumentsForCall(node).any(
    (argument) => const <String>{
      'label',
      'button',
      'link',
      'textField',
    }.contains(argument.name.lexeme),
  );

  bool _hasIconActionLabel(AstNode node, ArgumentList arguments) {
    if (_arguments(arguments)
        .any((argument) => argument.name.lexeme == 'tooltip')) {
      return true;
    }
    final icon = _arguments(arguments)
        .where((argument) => argument.name.lexeme == 'icon')
        .map((argument) => argument.argumentExpression)
        .where((expression) => _callName(expression) == 'Icon')
        .firstOrNull;
    if (icon != null &&
        _argumentsForCall(icon)
            .any((argument) => argument.name.lexeme == 'semanticLabel')) {
      return true;
    }
    return _hasEvidentSemantics(node, arguments);
  }

  Iterable<NamedArgument> _arguments(ArgumentList arguments) =>
      arguments.arguments.whereType<NamedArgument>();

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
      if (const <String>{
        'ThemeData',
        'ColorScheme',
        'ThemeExtension',
      }.contains(_callName(cursor))) {
        return true;
      }
      cursor = cursor.parent;
    }
    return false;
  }

  Iterable<NamedArgument> _argumentsForCall(AstNode node) => switch (node) {
    InstanceCreationExpression(:final argumentList) => _arguments(argumentList),
    MethodInvocation(:final argumentList) => _arguments(argumentList),
    _ => const <NamedArgument>[],
  };

  String? _callName(AstNode node) => switch (node) {
    InstanceCreationExpression(:final constructorName) =>
      constructorName.type.name.lexeme,
    MethodInvocation(target: null, :final methodName) => methodName.name,
    _ => null,
  };

  bool _isWidgetOwner(ClassDeclaration declaration) {
    final superclass = declaration.extendsClause?.superclass.name.lexeme;
    return const <String>{
      'State',
      'StatefulWidget',
      'StatelessWidget',
      'Widget',
    }.contains(superclass);
  }

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

  bool _insideWidgetOwner(AstNode node) {
    final owner = _enclosingClass(node);
    return owner != null && _isWidgetOwner(owner);
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

  bool _hasPreviewAnnotation(NodeList<Annotation> metadata) =>
      metadata.any((annotation) {
        final name = annotation.name.toSource().split('.').last;
        return !localTypes.contains(name) &&
            (name == 'DartitectPreviewMatrix' || name == 'Preview');
      });

  bool _looksLikeInfrastructureUri(String uri) =>
      const <String>{'dart:ffi', 'dart:io'}.contains(uri) ||
      RegExp(
        r'(?:^package:(?:dio|drift|firebase_core|http|objectbox|path_provider|shared_preferences|sqflite)/|/(?:adapter|adapters|infrastructure|remote|services?|stores?)/)',
      ).hasMatch(uri);

  bool _looksLikeOwnedResource(AstNode node) {
    final call = _callName(node);
    if (call != null &&
        const <String>{
          'AnimationController',
          'FocusNode',
          'ScrollController',
          'StreamSubscription',
          'TabController',
          'TextEditingController',
        }.contains(call)) {
      return true;
    }
    return node is MethodInvocation && node.methodName.name == 'listen';
  }

  bool _looksLikeDangerousCall(String? target, String? method) {
    final subject = '${target ?? ''}.${method ?? ''}';
    return RegExp(
          r'\b(?:Adapter|Backend|Client|Database|Dio|File|HttpClient|NativeTaskStore|RemoteService|Socket|Store)\b',
          caseSensitive: false,
        ).hasMatch(subject) ||
        method != null &&
            RegExp(
              r'^(?:connect|initializeGlobal|initializeNetwork|openDatabase|readAsBytes|readAsString|readSync|request|writeAsBytes|writeAsString)$',
            ).hasMatch(method);
  }

  bool _hasStaticBuilderWithoutChild(ArgumentList arguments) {
    if (_arguments(arguments)
        .any((argument) => argument.name.lexeme == 'child')) {
      return false;
    }
    final builder = _arguments(arguments)
        .where((argument) => argument.name.lexeme == 'builder')
        .map((argument) => argument.argumentExpression)
        .whereType<FunctionExpression>()
        .firstOrNull;
    if (builder == null) return false;
    final body = builder.body.toSource();
    final names = builder.parameters?.parameters
        .map((parameter) => parameter.name?.lexeme)
        .whereType<String>();
    return !(names?.any(
              (name) => RegExp('\\b${RegExp.escape(name)}\\b').hasMatch(body),
            ) ??
            false) &&
        !RegExp(r'\b(?:this|widget)\.').hasMatch(body);
  }

  bool _hasFiniteImageConstraint(InstanceCreationExpression node) {
    return _hasFiniteConstraint(node, node.argumentList);
  }

  bool _hasFiniteConstraint(AstNode node, ArgumentList arguments) {
    if (_arguments(arguments).any(
      (argument) =>
          const <String>{'height', 'width'}.contains(argument.name.lexeme),
    )) {
      return true;
    }
    var cursor = node.parent;
    for (var depth = 0; depth < 4 && cursor != null; depth += 1) {
      if (const <String>{
        'AspectRatio',
        'ConstrainedBox',
        'LimitedBox',
        'SizedBox',
      }.contains(_callName(cursor))) {
        return true;
      }
      cursor = cursor.parent;
    }
    return false;
  }

  static const _scrollableTypes = <String>{
    'CustomScrollView',
    'GridView',
    'ListView',
    'PageView',
    'SingleChildScrollView',
  };

  bool _hasIncompatibleScrollableAncestor(InstanceCreationExpression node) {
    return _hasIncompatibleScrollableAncestorCall(node, node.argumentList);
  }

  bool _hasIncompatibleScrollableAncestorCall(
    AstNode node,
    ArgumentList arguments,
  ) {
    final source = arguments.toSource();
    if (RegExp(r'physics\s*:\s*(?:const\s+)?NeverScrollableScrollPhysics\s*\(')
            .hasMatch(source) &&
        RegExp(r'shrinkWrap\s*:\s*true\b').hasMatch(source)) {
      return false;
    }
    final horizontal = RegExp(r'scrollDirection\s*:\s*Axis\.horizontal\b')
        .hasMatch(source);
    var cursor = node.parent;
    while (cursor != null) {
      final type = _callName(cursor);
      if (type != null && _scrollableTypes.contains(type)) {
        if (type == 'SingleChildScrollView') return false;
        final ancestorHorizontal = RegExp(
          r'scrollDirection\s*:\s*Axis\.horizontal\b',
        ).hasMatch(cursor.toSource());
        return horizontal == ancestorHorizontal;
      }
      cursor = cursor.parent;
    }
    return false;
  }

  bool _insideSetStateCallback(AstNode node) {
    var cursor = node.parent;
    while (cursor != null) {
      if (cursor is MethodInvocation && cursor.methodName.name == 'setState') {
        return true;
      }
      if (cursor is MethodDeclaration || cursor is FunctionDeclaration) {
        return false;
      }
      cursor = cursor.parent;
    }
    return false;
  }

  bool _isContextUseAfterAwait(SimpleIdentifier node) {
    final body = _enclosingFunctionBody(node);
    if (body == null) return false;
    final visitor = _CliAwaitOffsetVisitor(node.offset);
    body.accept(visitor);
    return visitor.latestEnd != null;
  }

  bool _hasBuildContextParameter(SimpleIdentifier node) {
    var cursor = node.parent;
    while (cursor != null) {
      final parameters = switch (cursor) {
        MethodDeclaration(:final parameters) => parameters,
        FunctionDeclaration(:final functionExpression) =>
          functionExpression.parameters,
        FunctionExpression(:final parameters) => parameters,
        _ => null,
      };
      if (parameters != null) {
        return parameters.parameters.any(
          (parameter) =>
              RegExp(r'\bBuildContext\s+context\b')
                  .hasMatch(parameter.toSource()),
        );
      }
      cursor = cursor.parent;
    }
    return false;
  }

  bool _isMountedAccess(SimpleIdentifier node) => switch (node.parent) {
    PrefixedIdentifier(:final prefix, :final identifier) =>
      identical(prefix, node) && identifier.name == 'mounted',
    PropertyAccess(:final target, :final propertyName) =>
      identical(target, node) && propertyName.name == 'mounted',
    _ => false,
  };

  bool _hasMountedGuard(SimpleIdentifier node) {
    final body = _enclosingFunctionBody(node);
    if (body == null) return false;
    final visitor = _CliAwaitOffsetVisitor(node.offset);
    body.accept(visitor);
    final awaitEnd = visitor.latestEnd;
    if (awaitEnd == null || awaitEnd > node.offset) return false;
    final start = awaitEnd;
    final end = node.offset;
    if (start < 0 || end > source.length || start > end) return false;
    return RegExp(
      r'if\s*\(\s*!\s*(?:context\s*\.\s*)?mounted\s*\)\s*(?:return\b|\{[^}]*\breturn\b)',
      dotAll: true,
    ).hasMatch(source.substring(start, end));
  }

  void _reportQuality(
    AstNode node,
    String code,
    String message,
    String remediation,
  ) => _report(node, code, FindingSeverity.warning, message, remediation);

  void _report(
    AstNode node,
    String code,
    FindingSeverity severity,
    String message,
    String remediation,
  ) {
    if (isSuppressed(code) || !_reportedCodes.add(code)) return;
    final location = lineAt(node.offset);
    onFinding(
      DartitectFinding(
        code: code,
        severity: severity,
        message: message,
        path: path,
        line: location.lineNumber,
        column: location.columnNumber,
        remediation: remediation,
      ),
    );
  }
}

final class _CliAwaitOffsetVisitor extends RecursiveAstVisitor<void> {
  _CliAwaitOffsetVisitor(this.beforeOffset);

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
