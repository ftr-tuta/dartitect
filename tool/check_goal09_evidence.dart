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
    'Future<DartitectFleetReport> previewUpgrade',
    'resolveSymbolicLinks',
    '_requireContained',
  ]) {
    if (!fleet.contains(marker))
      errors.add('Fleet marker is missing: $marker.');
  }
  for (final forbidden in const <String>[
    'Process.run',
    'HttpClient',
    'writeAsString',
    'writeAsBytes',
    'create(recursive:',
  ]) {
    if (fleet.contains(forbidden)) {
      errors.add('Read-only fleet service contains $forbidden.');
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
    if (!dispatcher.contains("case 'versions':") ||
        !dispatcher.contains("case 'check':") ||
        !dispatcher.contains("case 'policy':") ||
        !dispatcher.contains("case 'upgrade':") ||
        !dispatcher.contains("'dry-run'") ||
        dispatcher.contains("'apply'")) {
      errors.add('Fleet CLI is not read-only plus preview-only upgrade.');
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
  final canaries = _objects(canary['canaries']);
  const requiredCoverage = <String>{
    'flutter_simple',
    'objectbox_local_first',
    'outbox_sync',
    'desktop',
    'session_replacement',
    'noncooperative_cancellation',
    'large_assets',
    'multipackage_workspace',
    'consumer_owned_codegen',
  };
  final coverage = <String>{
    for (final entry in canaries) ..._strings(entry['coverage']),
  };
  if (!coverage.containsAll(requiredCoverage)) {
    errors.add('Goal 09 canary coverage is incomplete.');
  }
  final evidence = <String, List<String>>{
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
    '.github/workflows/ci.yaml': <String>[
      'flutter build linux',
      'flutter build windows',
      'flutter build macos',
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
          .contains('dart run dartitect_cli:dartitect model sync --apply')) {
    errors.add('Desktop or consumer-owned codegen canary command is missing.');
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
  if (lifecycle['samples'] != 5 ||
      diagnostics['samples'] != 5 ||
      _objects(models['results']).length != 4) {
    errors.add(
      'Create/dispose, diagnostics, or tooling samples are incomplete.',
    );
  }

  final distribution = read('docs/adr/0036-separate-cli-distribution.adoc');
  final cohorts = read('docs/adr/0037-release-validation-cohorts.adoc');
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

  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Goal 09 evidence passes: confined fleet, pinned policy, recoverable '
    'previews, nine real canary lanes, four benchmark areas, and release ADRs.',
  );
}

Map<String, Object?> _object(Object? value) => value! as Map<String, Object?>;

List<Map<String, Object?>> _objects(Object? value) =>
    (value! as List<Object?>).cast<Map<String, Object?>>();

List<String> _strings(Object? value) =>
    (value! as List<Object?>).cast<String>();
