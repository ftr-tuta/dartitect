import 'dart:io';

const _checkoutSha = '3d3c42e5aac5ba805825da76410c181273ba90b1';
const _flutterActionSha = '1a449444c387b1966244ae4d4f8c696479add0b2';
const _osvActionSha = 'ffa0a5f39214d80778c9b494822d94d0d9668458';
const _osvScannerSha = 'ffa0a5f39214d80778c9b494822d94d0d9668458';

/// Audits immutable Actions references and bounded OSV exceptions.
void main() {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final errors = <String>[];
  _auditWorkflows(root, errors);
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
  if (workflows.length != 2) {
    errors.add('Expected exactly two GitHub Actions workflows.');
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
    'Git consumption / v1.0.0-rc.3',
    'tool/run_git_canaries.dart',
  ]) {
    if (!ci.contains(required)) {
      errors.add('CI authorship audit is missing required policy: $required');
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
  final mergeCandidate = security
      .split('  osv-merge-candidate:')
      .last
      .split('  osv-trusted:')
      .first;
  if (mergeCandidate.contains('security-events: write') ||
      mergeCandidate.contains('upload-sarif: true')) {
    errors.add('Merge-candidate OSV scanning must remain read-only.');
  }
  if (!mergeCandidate.contains(
    'google/osv-scanner-action/osv-scanner-action@$_osvScannerSha',
  )) {
    errors.add('Merge-candidate OSV scanning must use the reviewed action.');
  }
  if (!mergeCandidate.contains("github.event_name == 'push'")) {
    errors.add('Merge-candidate OSV scanning must run on root/main pushes.');
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
