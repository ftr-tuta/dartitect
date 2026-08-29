import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/fix/fix.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:dartitect_modeling_analyzer/dartitect_modeling_analyzer.dart';

/// Analyzer-plugin projection of the shared Dartitect modeling compiler.
final class DartitectModelingRule extends MultiAnalysisRule {
  /// Creates the shared modeling rule set.
  DartitectModelingRule()
    : super(
        name: 'dartitect_modeling_contract',
        description: 'Applies the Dartitect semantic modeling compiler.',
      );

  /// Missing primary constructor; fix ID `model.migrate.primary` when safe.
  static const primaryConstructor = LintCode(
    'dartitect_dt1030',
    'DT1030: Modeling classes require an unnamed primary constructor.',
    correctionMessage: 'Apply the reviewed primary-constructor migration.',
    uniqueName: 'DartitectModelingRule.DT1030',
  );

  /// Analyzer could not resolve a required semantic element.
  static const unresolvedElement = LintCode(
    'dartitect_dt1039',
    'DT1039: Analyzer could not resolve the modeling declaration.',
    correctionMessage: 'Resolve syntax and dependency diagnostics first.',
    uniqueName: 'DartitectModelingRule.DT1039',
  );

  /// A homonymous annotation does not have Dartitect library identity.
  static const annotationIdentity = LintCode(
    'dartitect_dt1032',
    'DT1032: Modeling annotations must resolve to dartitect_modeling.',
    correctionMessage: 'Import the public dartitect_modeling entrypoint.',
    uniqueName: 'DartitectModelingRule.DT1032',
  );

  /// Modeling class modifier contract.
  static const classContract = LintCode(
    'dartitect_dt1033',
    'DT1033: Modeling classes must be concrete and final.',
    correctionMessage:
        'Make the annotated data carrier a concrete final class.',
    uniqueName: 'DartitectModelingRule.DT1033',
  );

  /// Defining-library part ownership contract.
  static const partContract = LintCode(
    'dartitect_dt1034',
    'DT1034: The defining library must own one deterministic Dartitect part.',
    correctionMessage: 'Declare the expected .dartitect.g.dart part once.',
    uniqueName: 'DartitectModelingRule.DT1034',
  );

  /// Primary constructor, inheritance, or mixin shape.
  static const declarationShape = LintCode(
    'dartitect_dt1035',
    'DT1035: The modeling declaration shape is invalid.',
    correctionMessage: 'Use the required unnamed primary and generated mixin.',
    uniqueName: 'DartitectModelingRule.DT1035',
  );

  /// Primary field declaration contract.
  static const fieldContract = LintCode(
    'dartitect_dt1036',
    'DT1036: Model fields must be public typed named final parameters.',
    correctionMessage: 'Move field ownership to the primary constructor.',
    uniqueName: 'DartitectModelingRule.DT1036',
  );

  /// Mutable collection interface retained by a model.
  static const mutableCollection = LintCode(
    'dartitect_dt1037',
    'DT1037: Model fields cannot retain mutable collection interfaces.',
    correctionMessage: 'Use a consumer-owned immutable value collection.',
    uniqueName: 'DartitectModelingRule.DT1037',
  );

  /// Generated name collision.
  static const generatedNameCollision = LintCode(
    'dartitect_dt1038',
    'DT1038: A model field collides with a generated member name.',
    correctionMessage: 'Rename the field explicitly.',
    uniqueName: 'DartitectModelingRule.DT1038',
  );

  /// Invalid or duplicate opt-in capability metadata.
  static const capabilityContract = LintCode(
    'dartitect_dt1040',
    'DT1040: Modeling capability metadata is invalid or ambiguous.',
    correctionMessage: 'Make each capability and rename explicit.',
    uniqueName: 'DartitectModelingRule.DT1040',
  );

  /// Traditional instance state remains in the class body.
  static const bodyState = LintCode(
    'dartitect_dt1041',
    'DT1041: Primary constructor fields must own all model instance state.',
    correctionMessage: 'Keep only behavior and static members in the body.',
    uniqueName: 'DartitectModelingRule.DT1041',
  );

  /// Unrelated Analyzer error prevents safe rendering.
  static const analyzerError = LintCode(
    'dartitect_dt1042',
    'DT1042: An Analyzer error prevents safe modeling generation.',
    correctionMessage: 'Resolve the underlying Analyzer diagnostic.',
    uniqueName: 'DartitectModelingRule.DT1042',
  );

  /// JSON type or consumer hook cannot be rendered safely.
  static const jsonCodecContract = LintCode(
    'dartitect_dt1043',
    'DT1043: JSON fields require a supported type or explicit hook pair.',
    correctionMessage: 'Provide validated consumer-owned decode/encode hooks.',
    uniqueName: 'DartitectModelingRule.DT1043',
  );

  /// Mapper target, compatibility, or consumer hook cannot be proven safe.
  static const mapperContract = LintCode(
    'dartitect_dt1044',
    'DT1044: Mapper fields require lossless compatibility or explicit hooks.',
    correctionMessage: 'Use semantically assignable fields or exact consumer-owned converters.',
    uniqueName: 'DartitectModelingRule.DT1044',
  );

  /// Stable compiler-rule to Analyzer-code mapping.
  static const Map<String, LintCode> codes = <String, LintCode>{
    'DT1030': primaryConstructor,
    'DT1032': annotationIdentity,
    'DT1033': classContract,
    'DT1034': partContract,
    'DT1035': declarationShape,
    'DT1036': fieldContract,
    'DT1037': mutableCollection,
    'DT1038': generatedNameCollision,
    'DT1039': unresolvedElement,
    'DT1040': capabilityContract,
    'DT1041': bodyState,
    'DT1042': analyzerError,
    'DT1043': jsonCodecContract,
    'DT1044': mapperContract,
  };

  @override
  List<DiagnosticCode> get diagnosticCodes => codes.values.toList();

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    if (!context.isInLibDir || context.isInTestDirectory) return;
    final visitor = _ModelingVisitor(this, context);
    registry
      ..addCompilationUnit(this, visitor)
      ..addClassDeclaration(this, visitor);
  }
}

final class _ModelingVisitor extends SimpleAstVisitor<void> {
  _ModelingVisitor(this.rule, this.context);

  final DartitectModelingRule rule;
  final RuleContext context;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    if (!identical(node, context.definingUnit.unit)) return;
    final hasModels = context.allUnits.any(
      (unit) => unit.unit.declarations.whereType<ClassDeclaration>().any(
        hasLexicalGeneratedModelAnnotation,
      ),
    );
    final diagnostic = ModelingCompiler.inspectLibraryPart(
      definingUnit: node,
      definingPath: context.definingUnit.file.path.replaceAll('\\', '/'),
      lineInfo: LineInfo.fromContent(context.definingUnit.content),
      hasModels: hasModels,
    );
    if (diagnostic != null) {
      rule.reportAtNode(
        node,
        diagnosticCode: DartitectModelingRule.partContract,
      );
    }
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (!hasLexicalModelingAnnotation(node)) return;
    final unit = context.currentUnit ?? context.definingUnit;
    final result = ModelingCompiler.inspectClass(
      declaration: node,
      sourcePath: unit.file.path.replaceAll('\\', '/'),
      lineInfo: LineInfo.fromContent(unit.content),
    );
    for (final diagnostic in result.diagnostics) {
      final code = DartitectModelingRule.codes[diagnostic.rule];
      if (code == null) continue;
      final offset = diagnostic.sourceOffset;
      final length = diagnostic.sourceLength;
      if (offset != null && length != null) {
        rule.reportAtOffset(offset, length, diagnosticCode: code);
      } else {
        rule.reportAtNode(node.namePart, diagnosticCode: code);
      }
    }
  }
}

/// Editor fix corresponding exactly to `model.migrate.primary`.
final class DartitectPrimaryConstructorFix extends ResolvedCorrectionProducer {
  /// Creates the fix for one DT1030 diagnostic.
  DartitectPrimaryConstructorFix({required super.context});

  static const FixKind _kind = FixKind(
    'dartitect.fix.model.migrate.primary',
    50,
    'Migrate to an unnamed primary constructor',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    AstNode? current = node;
    while (current != null && current is! ClassDeclaration) {
      current = current.parent;
    }
    if (current is! ClassDeclaration) return;
    final edits = primaryConstructorSourceEdits(current);
    if (edits == null) return;
    await builder.addDartFileEdit(file, (builder) {
      for (final edit in edits) {
        builder.addSimpleReplacement(
          SourceRange(edit.offset, edit.length),
          edit.replacement,
        );
      }
    });
  }
}
