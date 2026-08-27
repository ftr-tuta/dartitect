import 'dart:convert';
import 'dart:io';

import 'package:analysis_server_plugin/registry.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:dartitect_lints/main.dart';
import 'package:dartitect_lints/src/dartitect_boundary_rule.dart';
import 'package:dartitect_lints/src/ecosystem_policy.g.dart';
import 'package:dartitect_lints/src/generated_boundary_policy.dart';
import 'package:dartitect_lints/src/lint_boundary_config.dart';
import 'package:test/test.dart';

void main() {
  test('plugin registers one bounded warning rule with stable codes', () {
    final registry = _FakeRegistry();

    plugin.register(registry);

    expect(plugin.name, 'Dartitect architecture rules');
    expect(registry.warningRules, hasLength(1));
    expect(
      registry.warningRules.single.diagnosticCodes.map(
        (code) => code.lowerCaseName,
      ),
      <String>[
        'dartitect_domain_flutter_import',
        'dartitect_domain_infrastructure_import',
        'dartitect_data_presentation_import',
        'dartitect_presentation_infrastructure_import',
        'dartitect_build_context_boundary',
        'dartitect_forbidden_architecture_import',
        'dartitect_private_src_import',
        'dartitect_implementation_boundary',
        'dartitect_provider_type_boundary',
        'dartitect_flutter_type_boundary',
        'dartitect_architecture_codegen',
        'dartitect_provider_codegen_boundary',
        'dartitect_service_locator',
        'dartitect_scope_boundary',
        'dartitect_direct_console_logging',
        'dartitect_vendor_observability_import',
        'dartitect_empty_catch',
        'dartitect_sensitive_metadata_key',
        'dartitect_ecosystem_prohibited',
        'dartitect_ecosystem_exception',
        'dartitect_invalid_configuration',
      ],
    );
  });

  test('file-level parser recognizes only Dartitect suppressions', () {
    const source = '''
// ignore_for_file: dartitect_empty_catch, unnecessary_lambdas
// ignore_for_file: DARTITECT_VENDOR_OBSERVABILITY_IMPORT
// ignore: dartitect_direct_console_logging
void main() {}
''';

    expect(dartitectIgnoredDiagnosticsForFile(source), <String>{
      'dartitect_empty_catch',
      'dartitect_vendor_observability_import',
    });
  });

  test('shared classifier normalizes Windows paths', () {
    final classifier = DartitectBoundaryClassifier.defaults();

    expect(
      classifier
          .classify(r'lib\features\orders\orders_page.dart')
          .isLayer('presentation'),
      isTrue,
    );
    expect(classifier.classify(r'lib\main.dart').isCompositionRoot, isTrue);
    expect(
      classifier
          .classify(r'lib\features\orders\infrastructure\orders.g.dart')
          .isGeneratedInfrastructure,
      isTrue,
    );
  });

  test('generated infrastructure permits provider internals only', () {
    expect(
      DartitectBoundaryRule.generatedInfrastructureAllowsImport(
        'package:objectbox/internal.dart',
      ),
      isTrue,
    );
    expect(
      DartitectBoundaryRule.generatedInfrastructureAllowsImport(
        'features/tasks/infrastructure/task_records.dart',
      ),
      isTrue,
    );
    expect(
      DartitectBoundaryRule.generatedInfrastructureAllowsImport(
        'package:provider/src/provider.dart',
      ),
      isFalse,
    );
  });

  test('generated headers recognize reviewed generator suffixes', () {
    final root = Directory.systemTemp.createTempSync('dartitect-generated-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/dartitect.json').writeAsStringSync(
      jsonEncode(_config(compositionRoots: <String>['lib/main.dart'])),
    );
    final generated = File('${root.path}/lib/models/order.freezed.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('''// GENERATED CODE - DO NOT MODIFY BY HAND
class _OrderGenerated {}
''');

    expect(
      DartitectLintBoundaryResolver.classify(generated.path)
          .isGeneratedInfrastructure,
      isTrue,
    );
  });

  test('generated suffixes can be configured explicitly', () {
    final root = Directory.systemTemp.createTempSync(
      'dartitect-generated-config-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/dartitect.json').writeAsStringSync(
      jsonEncode(<String, Object?>{
        ..._config(compositionRoots: <String>['lib/main.dart']),
        'generatedSuffixes': <String>['.records.dart'],
      }),
    );
    final generated = File('${root.path}/lib/models/order.records.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('''// GENERATED CODE - DO NOT EDIT BY HAND.
class OrderRecords {}
''');

    expect(
      DartitectLintBoundaryResolver.classify(generated.path)
          .isGeneratedInfrastructure,
      isTrue,
    );
  });

  test('generated ecosystem policy honors scoped overlays and conflicts', () {
    final root = Directory.systemTemp.createTempSync('dartitect-policy-lint-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: consumer
dependencies:
  dartitect_dio: any
  sentry_dio: any
  pdf: any
''');
    final policyDirectory = Directory('${root.path}/.dartitect')..createSync();
    File('${policyDirectory.path}/ecosystem-policy.json').writeAsStringSync(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'entries': <Object?>[
          <String, Object?>{
            'package': 'pdf',
            'decision': 'approved',
            'owner': 'application team',
            'reason': 'isolated document adapter',
            'expiresOn': '2026-11-22',
            'paths': <String>['lib/infrastructure/documents/**'],
          },
        ],
      }),
    );
    final accepted = File(
      '${root.path}/lib/infrastructure/documents/pdf_adapter.dart',
    )..createSync(recursive: true);
    final rejected = File('${root.path}/lib/presentation/pdf_page.dart')
      ..createSync(recursive: true);
    const policy = DartitectLintEcosystemPolicy();

    expect(
      policy.explain('pdf', accepted.path).decision,
      DartitectEcosystemDecision.approved,
    );
    expect(
      policy.explain('pdf', rejected.path).decision,
      DartitectEcosystemDecision.reviewedException,
    );
    expect(policy.hasActiveConflict('sentry_dio', accepted.path), isTrue);
    expect(
      policy.explain('freezed', accepted.path).decision,
      DartitectEcosystemDecision.advisoryAlternative,
    );
    expect(
      policy.explain('listen', accepted.path).decision,
      DartitectEcosystemDecision.approvedPrimitive,
    );
  });

  test('lint resolver uses nearest config with project-relative paths', () {
    final temporary = Directory.systemTemp.createTempSync(
      'dartitect lint fixture çã 漢字 ',
    );
    addTearDown(() => temporary.deleteSync(recursive: true));
    final app = Directory('${temporary.path}/workspace/examples/app')
      ..createSync(recursive: true);
    File('${temporary.path}/workspace/dartitect.json').writeAsStringSync(
      jsonEncode(_config(compositionRoots: <String>['lib/outer.dart'])),
    );
    File('${app.path}/dartitect.json').writeAsStringSync(
      jsonEncode(
        _config(
          presentation: <String>['lib/features/**'],
          compositionRoots: <String>['lib/runtime/**'],
        ),
      ),
    );
    final page = File('${app.path}/lib/features/catalog/catalog.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('void catalog() {}\n');
    final runtime = File('${app.path}/lib/runtime/app_runtime.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('void runtime() {}\n');

    expect(
      DartitectLintBoundaryResolver.classify(page.path).isLayer('presentation'),
      isTrue,
    );
    expect(
      DartitectLintBoundaryResolver.classify(runtime.path).isCompositionRoot,
      isTrue,
    );
  });

  test('invalid config is explicit instead of a silent strict fallback', () {
    final root = Directory.systemTemp.createTempSync(
      'dartitect-invalid-lint-config-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/dartitect.json')
        .writeAsStringSync('{"configVersion": 2}');
    final source = File('${root.path}/lib/domain/model.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('class Model {}\n');

    final resolution = DartitectLintBoundaryResolver.resolve(source.path);

    expect(resolution.configurationError, isNotNull);
    expect(resolution.configurationError, isNot(contains(root.path)));
    expect(resolution.classification.isLayer('domain'), isTrue);
  });
}

Map<String, Object?> _config({
  List<String> presentation = const <String>['**/presentation/**'],
  required List<String> compositionRoots,
}) => <String, Object?>{
  'configVersion': 1,
  'profile': 'native_strict',
  'layers': <String, Object?>{
    'domain': <String>['**/domain/**'],
    'application': <String>['**/application/**'],
    'data': <String>['**/data/**'],
    'infrastructure': <String>['**/infrastructure/**'],
    'presentation': presentation,
  },
  'compositionRoots': compositionRoots,
  'generatedInfrastructure': <String>['lib/generated/**'],
};

final class _FakeRegistry implements PluginRegistry {
  final List<AbstractAnalysisRule> warningRules = <AbstractAnalysisRule>[];

  @override
  void registerWarningRule(AbstractAnalysisRule rule) => warningRules.add(rule);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
