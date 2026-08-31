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
        themeBoundary: _isThemeBoundary(path),
        flutterPresentationLibrary: parsed.unit.directives.any(
          (directive) => RegExp(
            r'''(?:import|export)\s+['"]package:flutter/(?:material|widgets|cupertino)\.dart['"]''',
          ).hasMatch(directive.toSource()),
        ),
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
    required this.themeBoundary,
    required this.flutterPresentationLibrary,
    required this.lineAt,
    required this.isSuppressed,
    required this.onFinding,
  });

  final String path;
  final bool themeBoundary;
  final bool flutterPresentationLibrary;
  final CharacterLocation Function(int offset) lineAt;
  final bool Function(String code) isSuppressed;
  final void Function(DartitectFinding finding) onFinding;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type.name.lexeme;
    _visitWidgetCall(type, node.argumentList, node);
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
    super.visitMethodInvocation(node);
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

  void _report(
    AstNode node,
    String code,
    FindingSeverity severity,
    String message,
    String remediation,
  ) {
    if (isSuppressed(code)) return;
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

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
