import 'dart:io';

const _checkoutSha = '3d3c42e5aac5ba805825da76410c181273ba90b1';
const _flutterActionSha = '1a449444c387b1966244ae4d4f8c696479add0b2';
const _osvActionSha = 'ffa0a5f39214d80778c9b494822d94d0d9668458';
const _osvScannerSha = 'ffa0a5f39214d80778c9b494822d94d0d9668458';
const _uploadArtifactSha = 'ea165f8d65b6e75b540449e92b4886f43607fa02';
const _downloadArtifactSha = 'd3f86a106a0bac45b974a628896c90dbdf5c8093';

/// Audits immutable Actions references and bounded OSV exceptions.
void main() {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final errors = <String>[];
  _auditWorkflows(root, errors);
  _auditHostedGatePolicy(root, errors);
  _auditOsvConfig(root, errors);
  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'CI security policy passed: external Actions use reviewed SHAs and OSV '
    'exceptions are bounded.',
  );
}

void _auditHostedGatePolicy(Directory root, List<String> errors) {
  final files = <File>[
    ...Directory('${root.path}/.github/workflows')
        .listSync(followLinks: false)
        .whereType<File>(),
    for (final path in const <String>[
      'tool/native_evidence_contract.json',
      'tool/actions_readiness_policy.json',
      'tool/rc_validation_contract.json',
      'tool/stable_candidate_contract.json',
      'tool/goal_gates.json',
      'README.md',
      'docs/implementation-status.adoc',
      'docs/release/1.0-readiness.adoc',
      'docs/release/native-device-evidence.adoc',
      'docs/release/installed-rc-validation.adoc',
      'docs/release/publication-runbook.adoc',
    ])
      File('${root.path}/$path'),
  ];
  for (final file in files) {
    if (!file.existsSync()) continue;
    final source = file.readAsStringSync();
    final relative = _relative(root, file);
    for (final forbidden in const <String>[
      'physical',
      'aparelho físico',
      'ADB_SERVER_SOCKET',
      '--device',
    ]) {
      if (source.toLowerCase().contains(forbidden.toLowerCase())) {
        errors.add(
          '$relative contains forbidden active-gate policy: $forbidden',
        );
      }
    }
    if (RegExp(r'runs-on:\s*(?:\[[^\]]*)?self-hosted').hasMatch(source)) {
      errors.add('$relative contains a self-hosted gate.');
    }
  }
}

void _auditWorkflows(Directory root, List<String> errors) {
  final workflowRoot = Directory('${root.path}/.github/workflows');
  final workflows =
      workflowRoot
          .listSync(followLinks: false)
          .whereType<File>()
          .where(
            (file) => file.path.endsWith('.yaml') || file.path.endsWith('.yml'),
          )
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  if (workflows.length != 3) {
    errors.add('Expected exactly three GitHub Actions workflows.');
  }
  for (final workflow in workflows) {
    final relative = _relative(root, workflow);
    final source = workflow.readAsStringSync();
    if (source.contains('pull_request_target:')) {
      errors.add('$relative must not use pull_request_target.');
    }
    if (source.contains(RegExp(r'runs-on:\s*[^\n]*-latest'))) {
      errors.add('$relative contains an unpinned hosted runner.');
    }
    if (RegExp(r'runs-on:\s*(?:\[[^\]]*)?self-hosted').hasMatch(source)) {
      errors.add('$relative must not use a self-hosted runner.');
    }
    for (final line in source.split(RegExp(r'\r?\n'))) {
      final match = RegExp(r'''^\s*(?:-\s*)?uses:\s*["']?([^\s#"']+)''')
          .firstMatch(line);
      if (match == null) continue;
      final locator = match.group(1)!;
      if (locator.startsWith('./')) continue;
      final separator = locator.lastIndexOf('@');
      if (separator < 1) {
        errors.add('$relative has an external Action without a ref: $locator');
        continue;
      }
      final action = locator.substring(0, separator);
      final reference = locator.substring(separator + 1);
      if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(reference)) {
        errors.add('$relative must pin $action to a full commit SHA.');
      }
      if (!RegExp(r'#\s*v\d+(?:\.\d+){1,2}\s*$').hasMatch(line)) {
        errors.add('$relative must preserve a version comment for $action.');
      }
      final expected = switch (action) {
        'actions/checkout' => _checkoutSha,
        'subosito/flutter-action' => _flutterActionSha,
        final value
            when value.startsWith(
              'google/osv-scanner-action/.github/workflows/',
            ) =>
          _osvActionSha,
        'google/osv-scanner-action/osv-scanner-action' => _osvScannerSha,
        'actions/upload-artifact' => _uploadArtifactSha,
        'actions/download-artifact' => _downloadArtifactSha,
        _ => null,
      };
      if (expected != null && reference != expected) {
        errors.add('$relative uses an unreviewed SHA for $action.');
      }
    }
  }

  final ci = File('${workflowRoot.path}/ci.yaml').readAsStringSync();
  for (final runner in const <String>[
    'ubuntu-24.04',
    'windows-2025',
    'macos-15',
  ]) {
    if (!ci.contains('runs-on: $runner')) {
      errors.add('CI does not pin required runner $runner.');
    }
  }
  for (final required in const <String>[
    'github.event.pull_request.head.sha',
    r'--author-revision=$AUTHOR_REVISION',
    'GITHUB_EVENT_NAME\" == \"merge_group',
    '--exclude-merge-commits',
    'Clean clone / release audit',
    'Git consumption / v1.0.0-rc.4',
    'tool/run_git_canaries.dart',
    'name: CI / Required',
    'android-media-current-emulator',
    'Drift Web / Chrome 2.34.3',
    'dart run tool/run_drift_web_fixture.dart',
    'system-images;android-34;google_apis;x86_64',
    'sdkmanager',
    'timeout 360',
    'for attempt in 1 2',
    'google/osv-scanner-action/osv-scanner-action@$_osvScannerSha',
    'tool/check_native_evidence.dart',
    'tool/create_actions_readiness.dart',
    'name: actions-readiness-v1',
    'retention-days: 90',
  ]) {
    if (!ci.contains(required)) {
      errors.add('CI authorship audit is missing required policy: $required');
    }
  }
  for (final job in const <String>[
    'linux',
    'windows',
    'macos',
    'android-emulator',
    'drift-web',
    'clean-clone',
    'git-consumption',
    'osv',
  ]) {
    if (!ci.contains('      - $job')) {
      errors.add('CI / Required does not depend on job $job.');
    }
  }
  if (ci.contains(r'ref: ${{ github.event.pull_request.head.sha }}')) {
    errors.add(
      'CI must build the checked-out merge candidate, not the PR head.',
    );
  }
  final security = File('${workflowRoot.path}/security.yaml')
      .readAsStringSync();
  for (final required in const <String>[
    '--config=./osv-scanner.toml',
    'fail-on-vuln: true',
    'upload-sarif: true',
    'cron: "12 12 * * 1"',
  ]) {
    if (!security.contains(required)) {
      errors.add('Security workflow is missing required policy: $required');
    }
  }
  for (final forbidden in const <String>[
    'pull_request:',
    'merge_group:',
    'push:',
    'osv-merge-candidate',
  ]) {
    if (security.contains(forbidden)) {
      errors.add(
        'Security is diagnostic-only and must not contain $forbidden.',
      );
    }
  }

  final publish = File('${workflowRoot.path}/publish.yaml').readAsStringSync();
  for (final required in const <String>[
    'workflow_dispatch:',
    'source_sha:',
    'ci_run_id:',
    'channel:',
    r'actions/runs/${CI_RUN_ID}',
    r'CI_RUN_ATTEMPT=$ci_run_attempt',
    '.name == "CI / Required" and .conclusion == "success"',
    r'run-id: ${{ inputs.ci_run_id }}',
    'tool/check_publication_readiness.dart',
    'GITHUB_ACTOR',
  ]) {
    if (!publish.contains(required)) {
      errors.add('Publish workflow is missing required policy: $required');
    }
  }

  final rulesetFile = File('${root.path}/tool/github_ruleset_policy.json');
  if (!rulesetFile.existsSync()) {
    errors.add('The checked main ruleset policy is missing.');
  } else {
    final source = rulesetFile.readAsStringSync();
    for (final required in const <String>[
      '"target": "refs/heads/main"',
      '"enforcement": "active"',
      '"bypassActors": []',
      '"requiredStatusChecks": ["CI / Required"]',
      '"strictRequiredStatusChecks": true',
    ]) {
      if (!source.contains(required)) {
        errors.add('The main ruleset policy is missing: $required');
      }
    }
  }
}

void _auditOsvConfig(Directory root, List<String> errors) {
  final config = File('${root.path}/osv-scanner.toml');
  if (!config.existsSync()) {
    errors.add('osv-scanner.toml is missing.');
    return;
  }
  final source = config.readAsStringSync();
  if (RegExp(
    r'^\s*\[\[\s*PackageOverrides\s*\]\]',
    multiLine: true,
  ).hasMatch(source)) {
    errors.add('OSV PackageOverrides are prohibited.');
  }
  if (RegExp(
    r'^\s*(?:ignore|vulnerability\.ignore|license\.ignore)\s*=\s*true\s*$',
    multiLine: true,
    caseSensitive: false,
  ).hasMatch(source)) {
    errors.add('OSV package-wide ignore switches are prohibited.');
  }

  final blocks = source.split(
    RegExp(r'^\s*\[\[\s*IgnoredVulns\s*\]\]\s*$', multiLine: true),
  );
  for (var index = 1; index < blocks.length; index += 1) {
    final block = blocks[index]
        .split(RegExp(r'^\s*\[\[', multiLine: true))
        .first;
    final values = <String, String>{};
    for (final line in block.split(RegExp(r'\r?\n'))) {
      final match = RegExp(
        r'''^\s*([A-Za-z][A-Za-z0-9]*)\s*=\s*["']?([^"'#]+?)["']?\s*(?:#.*)?$''',
      ).firstMatch(line);
      if (match != null) values[match.group(1)!] = match.group(2)!.trim();
    }
    final label = 'IgnoredVulns block $index';
    final id = values['id'];
    if (id == null || !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]+$').hasMatch(id)) {
      errors.add('$label requires one exact vulnerability id.');
    }
    final reason = values['reason'];
    if (reason == null || reason.length < 20 || !reason.contains('https://')) {
      errors.add('$label requires a justification and HTTPS analysis link.');
    }
    final rawUntil = values['ignoreUntil'];
    final ignoreUntil = rawUntil == null ? null : DateTime.tryParse(rawUntil);
    if (ignoreUntil == null) {
      errors.add('$label requires a valid ignoreUntil date.');
      continue;
    }
    final today = DateTime.now().toUtc();
    final start = DateTime.utc(today.year, today.month, today.day);
    final duration = ignoreUntil.toUtc().difference(start).inDays;
    if (duration < 0) errors.add('$label expired on $rawUntil.');
    if (duration > 30) errors.add('$label exceeds the 30-day maximum.');
  }
}

String _relative(Directory root, File file) => file.path
    .substring(root.path.length + 1)
    .replaceAll(Platform.pathSeparator, '/');
