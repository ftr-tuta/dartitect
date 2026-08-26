import 'dart:io';

const _required = <String>{
  'Dart',
  'Flutter',
  'analysis_server_plugin',
  'Dio',
  'ObjectBox',
  'crypto',
  'GitHub Actions checkout',
  'Flutter Action',
  'OSV Scanner Action',
  'Sentry Dart',
  'Codex skills format',
  'dart_mcp',
  'Codex MCP',
};

void main(List<String> arguments) {
  final root = File.fromUri(Platform.script).parent.parent;
  final fixture = File(
    '${root.path}/tool/fixtures/source-ledger-unavailable.adoc',
  );
  final fixtureAudit = _audit(
    fixture.readAsStringSync(),
    requireCompleteSet: false,
  );
  if (!fixtureAudit.errors.contains(
    'Dio is required but its source status is UNVERIFIED',
  )) {
    stderr.writeln(
      'Source-unavailable fixture did not block required-source adoption.',
    );
    exitCode = 1;
    return;
  }

  final ledger = File(
    arguments.isEmpty
        ? '${root.path}/docs/research/source-ledger.adoc'
        : arguments.single,
  );
  final audit = _audit(ledger.readAsStringSync(), requireCompleteSet: true);
  if (audit.errors.isNotEmpty) {
    stderr.writeln(audit.errors.join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Source ledger passed: ${audit.rowCount} attributed entries; '
    'unavailable-source fixture blocks adoption.',
  );
}

({List<String> errors, int rowCount}) _audit(
  String source, {
  required bool requireCompleteSet,
}) {
  final rows = source
      .split(RegExp(r'\r?\n'))
      .where((line) => line.startsWith('| ') && !line.startsWith('| Subject'))
      .toList();
  final subjects = <String>{};
  final errors = <String>[];
  for (final row in rows) {
    final cells = row.split('|').skip(1).map((cell) => cell.trim()).toList();
    if (cells.length != 5) {
      errors.add('row does not have 5 cells: $row');
      continue;
    }
    final subject = cells[0];
    if (!subjects.add(subject)) errors.add('duplicate subject: $subject');
    if (cells[1].isEmpty) errors.add('$subject has no version');
    if (!cells[2].contains('https://')) {
      errors.add('$subject has no source link');
    }
    if (!RegExp(r'^20\d\d-\d\d-\d\d$').hasMatch(cells[3])) {
      errors.add('$subject has an invalid verification date');
    }
    final status = cells[4];
    if (!RegExp(r'^(VERIFIED|DEFER|UNVERIFIED)').hasMatch(status)) {
      errors.add('$subject has an invalid status');
    }
    if (_required.contains(subject) && status.startsWith('UNVERIFIED')) {
      errors.add('$subject is required but its source status is UNVERIFIED');
    }
  }
  if (requireCompleteSet) {
    final missing = _required.difference(subjects);
    if (missing.isNotEmpty) {
      errors.add('missing subjects: ${missing.join(', ')}');
    }
  }
  return (errors: errors, rowCount: rows.length);
}
