import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final stableCohort = _cohortVersion(root) == '1.0.0';
  final skipGet = arguments.contains('--skip-get');
  final web = arguments.contains('--web');
  final nativeObjectBox = arguments.contains('--native-objectbox');
  final commands = <_Command>[
    if (!skipGet) const _Command('dart', <String>['pub', 'get']),
    const _Command('dart', <String>[
      'format',
      '--output=none',
      '--set-exit-if-changed',
      '.',
    ]),
    const _Command('flutter', <String>['analyze']),
    const _Command('dart', <String>['run', 'tool/check_goal_gates.dart']),
    const _Command('dart', <String>['run', 'tool/check_optional_slices.dart']),
    const _Command('dart', <String>['run', 'tool/check_goal09_evidence.dart']),
    const _Command('dart', <String>[
      'run',
      'tool/check_technical_hardening_readiness.dart',
    ]),
    const _Command('dart', <String>['run', 'tool/check_package_topology.dart']),
    const _Command('dart', <String>[
      'run',
      'tool/check_provider_constructor_evidence.dart',
    ]),
    const _Command('dart', <String>[
      'run',
      'tool/check_package_release_contract.dart',
    ]),
    if (!stableCohort)
      const _Command('dart', <String>['run', 'tool/check_rc_candidate.dart']),
    const _Command('dart', <String>['run', 'tool/check_pub_dev_identity.dart']),
    const _Command('dart', <String>['run', 'tool/check_ecosystem_policy.dart']),
    const _Command('dart', <String>[
      'run',
      'tool/check_consumer_neutrality.dart',
    ]),
    const _Command('dart', <String>[
      'run',
      'tool/check_sdk_inventory.dart',
      '--check',
    ]),
    const _Command('dart', <String>['run', 'tool/check_testing_matrices.dart']),
    const _Command('dart', <String>[
      'run',
      'tool/generate_boundary_policy.dart',
      '--check',
    ]),
    const _Command('dart', <String>[
      'run',
      'tool/check_benchmark_artifacts.dart',
    ]),
    const _Command('dart', <String>['run', 'tool/check_model_benchmark.dart']),
    const _Command('dart', <String>[
      '--enable-asserts',
      'run',
      'tool/benchmark_diagnostics.dart',
      'debug',
    ]),
    const _Command('dart', <String>[
      'run',
      'tool/benchmark_diagnostics.dart',
      'profile',
    ]),
    const _Command('dart', <String>[
      '--enable-asserts',
      'run',
      'tool/benchmark_lifecycle_churn.dart',
      'debug',
    ]),
    const _Command('dart', <String>[
      'run',
      'tool/benchmark_lifecycle_churn.dart',
      'profile',
    ]),
    const _Command('dart', <String>[
      'run',
      'tool/check_pure_dart_hardening.dart',
    ]),
    const _Command('dart', <String>[
      'run',
      'tool/check_runtime_hardening.dart',
    ]),
    const _Command('dart', <String>[
      'run',
      'tool/check_native_evidence.dart',
      '--contract-only',
    ]),
    const _Command('dart', <String>['run', 'tool/check_source_ledger.dart']),
    const _Command('dart', <String>[
      'run',
      'tool/check_dependency_inventory.dart',
    ]),
    const _Command('dart', <String>['run', 'tool/check_skill_coverage.dart']),
    const _Command('dart', <String>['run', 'tool/check_public_docs.dart']),
    if (!stableCohort)
      const _Command('dart', <String>[
        'run',
        'tool/check_rc_readiness.dart',
        '--contract-only',
      ]),
    if (!stableCohort)
      const _Command('dart', <String>[
        'run',
        'tool/check_rc_validation.dart',
        '--contract-only',
      ]),
    const _Command('dart', <String>[
      'run',
      'tool/check_stable_candidate.dart',
      '--contract-only',
    ]),
    const _Command('dart', <String>[
      'test',
      'tool/setup_objectbox_vm_test.dart',
    ]),
    const _Command('dart', <String>[
      'test',
      'tool/check_provider_constructor_evidence_test.dart',
    ]),
    const _Command('dart', <String>['test', 'tool/release_audit_test.dart']),
    const _Command('dart', <String>[
      'test',
      'tool/check_package_release_contract_test.dart',
    ]),
    const _Command('dart', <String>['test', 'tool/check_goal_gates_test.dart']),
    const _Command('dart', <String>[
      'test',
      'tool/check_native_evidence_test.dart',
    ]),
    const _Command('dart', <String>[
      'test',
      'tool/run_native_ci_evidence_test.dart',
    ]),
    const _Command('dart', <String>[
      'test',
      'tool/git_dependency_overrides_test.dart',
    ]),
    const _Command('dart', <String>[
      'test',
      'tool/check_stable_candidate_test.dart',
    ]),
    const _Command('dart', <String>[
      'test',
      'tool/check_rc_readiness_test.dart',
      'tool/check_publication_readiness_test.dart',
    ]),
    const _Command('dart', <String>[
      'test',
      'tool/check_rc_validation_test.dart',
    ]),
    const _Command('dart', <String>[
      'run',
      'tool/generate_mcp_catalog.dart',
      '--check',
    ]),
    const _Command('dart', <String>['run', 'tool/check_api_snapshot.dart']),
    for (final package in <String>[
      'dartitect',
      'dartitect_sync',
      'dartitect_testing',
      'dartitect_cli',
      'dartitect_lints',
      'dartitect_dio',
      'dartitect_isolates',
      'dartitect_locale_br',
      'dartitect_geometry',
      'dartitect_observability',
      'dartitect_drift',
      'dartitect_sentry',
      'dartitect_mcp',
    ])
      _Command('dart', <String>['test', 'packages/$package']),
    for (final package in <String>[
      'dartitect_flutter',
      'dartitect_objectbox',
      'dartitect_privacy',
      'dartitect_media',
    ])
      _Command('flutter', <String>['test', 'packages/$package']),
    const _Command('flutter', <String>['test', 'examples/reference_app']),
    if (nativeObjectBox)
      _Command(
        'flutter',
        const <String>[
          'test',
          'test/native_objectbox_workload_test.dart',
          'test/drift_objectbox_bounded_contexts_test.dart',
        ],
        workingDirectory: 'examples/reference_app',
        environment: _nativeObjectBoxEnvironment(root),
      ),
    const _Command('flutter', <String>['test', 'examples/adapters_app']),
    const _Command('flutter', <String>[
      'test',
      'tool/canaries/native_capabilities/test',
    ]),
    const _Command('dart', <String>[
      'test',
      'examples/model_generator_fixture',
    ]),
    const _Command('dart', <String>[
      'test',
      'tool/check_boundary_parity_test.dart',
    ]),
    const _Command('dart', <String>['run', 'tool/check_boundary_parity.dart']),
    const _Command('dart', <String>[
      'run',
      'tool/run_drift_native_fixture.dart',
    ]),
    if (nativeObjectBox)
      const _Command('flutter', <String>[
        'test',
      ], workingDirectory: 'tool/objectbox_native_fixture'),
    const _Command('dart', <String>[
      'run',
      'dartitect_cli:dartitect',
      'inspect',
      '--json',
      '--root',
      'examples/reference_app',
    ]),
    const _Command('dart', <String>[
      'run',
      'dartitect_cli:dartitect',
      'model',
      'check',
      '--root',
      'examples/model_generator_fixture',
    ]),
    const _Command('dart', <String>[
      'run',
      'dartitect_cli:dartitect',
      'codex',
      'sync',
      '--dry-run',
    ]),
    if (web)
      const _Command('dart', <String>[
        'run',
        'tool/run_drift_web_fixture.dart',
      ]),
    if (web)
      for (final package in <String>[
        'dartitect',
        'dartitect_testing',
        'dartitect_locale_br',
        'dartitect_geometry',
      ])
        _Command('dart', const <String>[
          'test',
          '--platform',
          'chrome',
        ], workingDirectory: 'packages/$package'),
  ];

  for (final command in commands) {
    stdout.writeln('\n> ${command.executable} ${command.arguments.join(' ')}');
    final process = await Process.start(
      command.executable,
      command.arguments,
      workingDirectory: command.workingDirectory == null
          ? root.path
          : '${root.path}${Platform.pathSeparator}'
                '${command.workingDirectory!.replaceAll('/', Platform.pathSeparator)}',
      mode: ProcessStartMode.inheritStdio,
      // Flutter is exposed as a batch wrapper on Windows. Dart's direct
      // process launcher does not resolve that wrapper without the shell.
      runInShell: Platform.isWindows && command.executable == 'flutter',
      environment: command.environment,
    );
    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      stderr.writeln('Verification stopped with exit code $exitCode.');
      exit(exitCode);
    }
  }
  stdout.writeln('\nDartitect workspace verification passed.');
}

String _cohortVersion(Directory root) {
  final value = jsonDecode(
    File('${root.path}/tool/package_release_contract.json').readAsStringSync(),
  );
  if (value is! Map<String, Object?> || value['cohortVersion'] is! String) {
    throw const FormatException('Invalid package release cohort.');
  }
  return value['cohortVersion']! as String;
}

Map<String, String> _nativeObjectBoxEnvironment(Directory root) {
  final libraryDirectory =
      '${root.path}${Platform.pathSeparator}tool'
      '${Platform.pathSeparator}objectbox_native_fixture'
      '${Platform.pathSeparator}lib';
  final environment = <String, String>{'DARTITECT_NATIVE_OBJECTBOX': '1'};
  if (Platform.isWindows) {
    environment['PATH'] = _prependEnvironmentPath(
      libraryDirectory,
      'PATH',
      ';',
    );
  } else if (Platform.isMacOS) {
    environment['DYLD_LIBRARY_PATH'] = _prependEnvironmentPath(
      libraryDirectory,
      'DYLD_LIBRARY_PATH',
      ':',
    );
  } else {
    environment['LD_LIBRARY_PATH'] = _prependEnvironmentPath(
      libraryDirectory,
      'LD_LIBRARY_PATH',
      ':',
    );
  }
  return environment;
}

String _prependEnvironmentPath(String value, String key, String separator) {
  final inherited = Platform.environment[key];
  return inherited == null || inherited.isEmpty
      ? value
      : '$value$separator$inherited';
}

final class _Command {
  const _Command(
    this.executable,
    this.arguments, {
    this.workingDirectory,
    this.environment,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;
}
