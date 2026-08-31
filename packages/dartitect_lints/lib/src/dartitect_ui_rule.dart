import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
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
  ];

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    if (!context.isInLibDir || context.isInTestDirectory) return;
    final visitor = _UiVisitor(this, context);
    registry
      ..addInstanceCreationExpression(this, visitor)
      ..addMethodInvocation(this, visitor)
      ..addPrefixedIdentifier(this, visitor)
      ..addSimpleIdentifier(this, visitor);
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
    if (!_flutterPresentationLibrary ||
        !_isSizingDecision(node) ||
        node.name != 'defaultTargetPlatform' && node.name != 'kIsWeb') {
      return;
    }
    if (_isFlutter(node.element, 'foundation.dart')) {
      _report(node, DartitectUiRule.devicePlatformSizing, 'DT3102');
    }
  }

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
        _resolution.suppressedCodes.contains(stableCode)) {
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

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
