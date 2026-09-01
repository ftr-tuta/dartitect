import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

void main() {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final errors = <String>[];
  String read(String path) {
    final file = File('${root.path}/$path');
    if (!file.existsSync()) {
      errors.add('Missing Goal 09 evidence: $path.');
      return '';
    }
    return file.readAsStringSync();
  }

  final fleet = read('packages/dartitect_cli/lib/src/fleet/fleet_service.dart');
  final runner = read(
    'packages/dartitect_cli/lib/src/cli/dartitect_cli_runner.dart',
  );
  for (final marker in const <String>[
    'Future<DartitectFleetReport> versions',
    'Future<DartitectFleetReport> check',
    'Future<DartitectFleetReport> policy',
    'Future<DartitectFleetReport> inventory',
    'Future<DartitectFleetReport> impact({',
    'Future<DartitectFleetReport> previewUpgrade',
    'Future<DartitectFleetReport> applyUpgrade',
    'resolveSymbolicLinks',
    '_requireContained',
    '_withFleetLocks',
    '_FleetSnapshot.capture',
    '_writeFleetJournal',
    '_recoverFleetJournalIfNeeded',
    '_validateProjectDigests',
    '_validationCommands',
    '_sanitizeOutput',
  ]) {
    if (!fleet.contains(marker))
      errors.add('Fleet marker is missing: $marker.');
  }
  for (final forbidden in const <String>['HttpClient']) {
    if (fleet.contains(forbidden)) {
      errors.add('Offline fleet service contains $forbidden.');
    }
  }
  final fleetRunnerStart = runner.indexOf('Future<int> _fleet(');
  final fleetRunnerEnd = runner.indexOf(
    'static String _fleetProjectSummary',
    fleetRunnerStart,
  );
  if (fleetRunnerStart < 0 || fleetRunnerEnd < 0) {
    errors.add('Fleet CLI dispatcher is missing.');
  } else {
    final dispatcher = runner.substring(fleetRunnerStart, fleetRunnerEnd);
    if (!dispatcher.contains("case 'report':") ||
        !dispatcher.contains("case 'versions':") ||
        !dispatcher.contains("case 'check':") ||
        !dispatcher.contains("case 'policy':") ||
        !dispatcher.contains("case 'inventory':") ||
        !dispatcher.contains("case 'impact':") ||
        !dispatcher.contains("case 'upgrade':") ||
        !dispatcher.contains("'dry-run'") ||
        !dispatcher.contains("'apply'") ||
        !dispatcher.contains("'to'")) {
      errors.add('Fleet CLI lacks transactional preview/apply upgrade gates.');
    }
  }

  final bundleFile = File('${root.path}/tool/fleet_policy_bundle.json');
  final bundle = _object(jsonDecode(read('tool/fleet_policy_bundle.json')));
  if (bundle['schemaVersion'] != 1 ||
      bundle['bundleVersion'] is! String ||
      bundle['policyPath'] != 'ecosystem_policy.json' ||
      bundle['policySha256'] is! String ||
      bundle['blockUnreviewed'] is! bool) {
    errors.add('Fleet policy bundle schema is invalid.');
  } else {
    final policy = File('${bundleFile.parent.path}/${bundle['policyPath']}');
    if (!policy.existsSync() ||
        sha256.convert(policy.readAsBytesSync()).toString() !=
            bundle['policySha256']) {
      errors.add('Fleet policy bundle does not pin its policy bytes.');
    }
  }

  final projectService = read(
    'packages/dartitect_cli/lib/src/project/dartitect_project_service.dart',
  );
  for (final marker in const <String>[
    'dependencyUpgrade',
    'previewDependencyUpgrade',
    'project-change.lock',
    'dependency-upgrade.pubspec.stage',
    'dependency-upgrade.pubspec.backup',
    'dependency-upgrade.transaction.json',
    "'stale_plan'",
  ]) {
    if (!projectService.contains(marker)) {
      errors.add('Recoverable upgrade marker is missing: $marker.');
    }
  }

  final sarif = read('packages/dartitect_cli/lib/src/diagnostics/sarif.dart');
  for (final marker in const <String>[
    "'2.1.0'",
    "'https://json.schemastore.org/sarif-2.1.0.json'",
    '_relativeUri(finding.path)',
    '_message(finding.message)',
  ]) {
    if (!sarif.contains(marker))
      errors.add('SARIF marker is missing: $marker.');
  }

  final canary = _object(
    jsonDecode(read('tool/canaries/canary_contract.json')),
  );
  final release = _object(
    jsonDecode(read('tool/package_release_contract.json')),
  );
  final workspaceCohort = _object(release['workspaceCohort']);
  final canaries = _objects(canary['canaries']);
  final requiredCoverage = <String>{
    'pure_dart_modeling',
    'json',
    'projection',
    'mapper',
    'chrome',
    'clean_clone',
    'offline_hybrid_generated_wiring',
    'all_opt_in_capabilities',
    'six_platform_scaffold',
    'consumer_owned_wiring_absence',
    'workmanager_preview_and_unsupported',
    'wiring_noop_zero_writes',
    'main_paved_road_15_lines',
    'large_30_feature_matrix',
    'application_session_context_ownership',
    'web_linux_incremental_builds',
    'openapi_feature_selection',
    'typed_openapi_operation_runtime',
    'renderer_migration_chain',
    'induced_error_bound',
    'flutter_simple',
    'flutter_mvvm',
    'objectbox_local_first',
    'objectbox_primary_evidence',
    'drift_objectbox_bounded_contexts',
    'mixed_dartitect_objectbox_drift',
    'drift_provider_package',
    'drift_consumer_owned_schema',
    'drift_sync_ports',
    'outbox_sync',
    'desktop',
    'session_replacement',
    'noncooperative_cancellation',
    'large_assets',
    'multipackage_workspace',
    'consumer_owned_codegen',
    'native_capabilities',
    'dio_adapter',
    'objectbox_adapter',
    'sentry_fake_hub',
    'media_privacy_adapters',
    'devtools_entrypoint',
    'lints_entrypoint',
    'mcp_entrypoint',
    'testing_entrypoint',
    'openapi_renderer',
    'tooling_commands',
  };
  if (workspaceCohort['channel'] == 'stable') {
    requiredCoverage.add('fleet_upgrade_zero_residual');
  }
  final coverage = <String>{
    for (final entry in canaries) ..._strings(entry['coverage']),
  };
  if (!coverage.containsAll(requiredCoverage)) {
    errors.add('Goal 09 canary coverage is incomplete.');
  }
  if (canaries.length != 9) {
    errors.add('Goal 09 requires all nine isolated packaged canaries.');
  }
  final evidence = <String, List<String>>{
    'examples/model_generator_fixture/test/user_test.dart': <String>[
      'generated equality',
      'JSON codec round-trips',
      'descriptor projection lens and mapper',
    ],
    'examples/thin_consumer_canary/test/thin_consumer_canary_test.dart':
        <String>[
          'TasksFeatureWiring.capabilities',
          'DartitectWorkmanagerPlatform.windows',
        ],
    'examples/thin_consumer_canary/lib/main.dart': <String>[
      'runDartitectApplication',
    ],
    'tool/canaries/minimal/lib/main.dart': <String>['CompositionRoot'],
    'tool/canaries/minimal/test/hardening_canary_test.dart': <String>[
      '8 * 1024 * 1024',
      'workspace:',
      'non-cooperative',
    ],
    'examples/reference_app/test/offline_first_session_test.dart': <String>[
      'offline mutation reconnects',
      '10k sync, isolate projection',
    ],
    'examples/reference_app/test/widget_test.dart': <String>[
      'forced logout removes nested routes before session drain',
    ],
    'examples/reference_app/test/native_objectbox_workload_test.dart': <String>[
      'ObjectBox',
    ],
    'examples/reference_app/test/drift_objectbox_bounded_contexts_test.dart':
        <String>['separate bounded contexts without dual writes'],
    'tool/canaries/large_consumer_source/test/large_consumer_test.dart':
        <String>[
          '30 concrete feature graphs open and close with exact scopes',
          'isA<GetProbeOperation>()',
          'census.verifyZero()',
        ],
    'tool/canaries/large_consumer_source/tool/verify_large_preview.dart':
        <String>['featureOutputs.length != 30', 'inducedError.length >= 512'],
    'packages/dartitect_cli/test/fleet_service_test.dart': <String>[
      'service.inventory',
      'service.impact',
      'fleet records every renderer migration including no-op steps',
    ],
    'examples/adapters_app/lib/runtime/adapters_runtime.dart': <String>[
      'final hub = Hub(',
      '_DiscardingSentryTransport',
    ],
    'tool/canaries/tooling_source/lib/tooling_probe.dart': <String>[
      'DartitectDevToolsRegistration',
      'DartitectMcpPolicy',
      'ResourceCensus',
    ],
    'tool/canaries/tooling_source/test/renderer_catalog_test.dart': <String>[
      'operation.rendererId',
      'blueprint.renderer-canary.template',
      'generation.unmanaged-output',
    ],
    'tool/provider_constructor_evidence/objectbox_5_3_2_primary.dart.fixture':
        <String>['final class FixtureEntity({', '@Id() var id'],
    '.github/workflows/ci.yaml': <String>[
      'flutter build linux',
      'flutter build windows',
      'flutter build macos',
      'dart test --platform chrome',
      'packages/dartitect_modeling',
    ],
  };
  for (final entry in evidence.entries) {
    final source = read(entry.key);
    for (final marker in entry.value) {
      if (!source.contains(marker)) {
        errors.add('${entry.key} lacks real canary marker: $marker.');
      }
    }
  }
  if (!jsonEncode(canary).contains('flutter build host-desktop') ||
      !jsonEncode(canary)
          .contains('dart run dartitect_cli:dartitect model sync --apply') ||
      !jsonEncode(canary).contains('dartitect verify --json')) {
    errors.add(
      'Desktop, consumer-owned codegen, or read-only verify canary is missing.',
    );
  }

  final raw = _object(
    jsonDecode(read('tool/benchmark_workspace/artifacts/raw.json')),
  );
  for (final section in const <String>[
    'fanout',
    'workloads',
    'commands',
    'resourceCensus',
  ]) {
    if (!raw.containsKey(section)) {
      errors.add('Benchmark section is missing: $section.');
    }
  }
  final workloads = _object(raw['workloads']);
  if (!workloads.keys.toSet().containsAll(const <String>{
    'writes',
    'signals',
    'family',
  })) {
    errors.add('Transaction/resource benchmark workloads are incomplete.');
  }
  final environment = _object(
    jsonDecode(read('tool/benchmark_workspace/artifacts/environment.json')),
  );
  if (environment['publicClaimEligible'] != false ||
      environment['claimPolicy'] != 'INTERNAL_GATE_ONLY') {
    errors.add('Benchmarks marked for reproduction could feed public claims.');
  }
  final lifecycle = _object(
    jsonDecode(read('tool/lifecycle_churn_benchmark_contract.json')),
  );
  final diagnostics = _object(
    jsonDecode(read('tool/diagnostics_benchmark_contract.json')),
  );
  final models = _object(jsonDecode(read('tool/model_benchmark.json')));
  final modelPolicy = _object(models['policy']);
  final baselineModels = _object(models['baseline']);
  final candidateModels = _object(models['candidate']);
  if (lifecycle['samples'] != 5 ||
      diagnostics['samples'] != 5 ||
      models['schemaVersion'] != 2 ||
      modelPolicy['coldRuns'] != 5 ||
      modelPolicy['warmRuns'] != 20 ||
      modelPolicy['maxRegressionPercent'] != 10.0 ||
      modelPolicy['cacheAuthority'] != false ||
      baselineModels['implementation'] != 'legacy-core-modeling' ||
      candidateModels['implementation'] != 'modular-modeling' ||
      _objects(baselineModels['results']).length != 4 ||
      _objects(candidateModels['results']).length != 4 ||
      _objects(models['comparisons'])
          .any((comparison) => comparison['status'] != 'pass')) {
    errors.add(
      'Create/dispose, diagnostics, or tooling samples are incomplete.',
    );
  }

  final distribution = read('docs/adr/0036-separate-cli-distribution.adoc');
  final cohorts = read('docs/adr/0037-release-validation-cohorts.adoc');
  final adoption = read('docs/adr/0042-rc4-adoption-and-evidence.adoc');
  if (!distribution.contains('separate executable package') ||
      !distribution.contains('will not distribute one for 1.0') ||
      !distribution.contains('no fleet bootstrap')) {
    errors.add('CLI distribution evaluation is incomplete.');
  }
  for (final marker in const <String>[
    '* runtime:',
    '* Flutter:',
    '* tooling:',
    '* adapters:',
    'one lockstep',
  ]) {
    if (!cohorts.contains(marker)) {
      errors.add('Release cohort ADR marker is missing: $marker.');
    }
  }
  for (final marker in const <String>[
    'recommended_complete',
    'native_strict',
    'strictly read-only aggregate gate',
    'twenty warm incremental runs',
    'above 10%',
  ]) {
    if (!adoption.contains(marker)) {
      errors.add('RC4 adoption ADR marker is missing: $marker.');
    }
  }

  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Goal 09 evidence passes: confined transactional fleet, pinned policy, '
    'journaled rollback, nine formal isolated canaries plus provider/workspace fixtures, '
    'same-host 5/20 benchmarks, and release ADRs.',
  );
}

Map<String, Object?> _object(Object? value) => value! as Map<String, Object?>;

List<Map<String, Object?>> _objects(Object? value) =>
    (value! as List<Object?>).cast<Map<String, Object?>>();

List<String> _strings(Object? value) =>
    (value! as List<Object?>).cast<String>();
