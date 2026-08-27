import 'dart:convert';
import 'dart:io';

void main() {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final errors = <String>[];
  Map<String, Object?> object(String path) {
    final value = jsonDecode(File('${root.path}/$path').readAsStringSync());
    if (value is! Map<String, Object?>) {
      throw FormatException('$path must contain one JSON object.');
    }
    return value;
  }

  final readiness = object('tool/technical_hardening_readiness.json');
  final local = readiness['localImplementation'];
  final binding = readiness['candidateBinding'];
  final authority = readiness['authority'];
  final blockers = readiness['externalBlockers'];
  if (readiness['schemaVersion'] != 1 ||
      readiness['status'] != 'NOT_READY' ||
      local is! Map<String, Object?> ||
      binding is! Map<String, Object?> ||
      authority is! Map<String, Object?> ||
      blockers is! List<Object?> ||
      blockers.length != 5) {
    errors.add(
      'Technical hardening readiness must remain exact and fail-closed.',
    );
  } else {
    final goals = (local['goals']! as List<Object?>).cast<String>();
    if (goals.join(',') != '00,01,02,03,04,05,06,07,08,09,10' ||
        local['selectedFindings'] != 'FIXED' ||
        local['optionalSlices'] != 'DEFERRED' ||
        binding['status'] != 'EXACT_SHA_RECEIPT_REQUIRED' ||
        binding['sourceSha'] != null ||
        binding['sourceTree'] != null ||
        authority['tagCreated'] != false ||
        authority['githubReleaseCreated'] != false ||
        authority['pubDevPublished'] != false ||
        authority['distributionAuthorized'] != false ||
        authority['humanDecisionRequired'] != true) {
      errors.add('Technical hardening readiness overstates local authority.');
    }
  }
  final rc = object('tool/rc_readiness_decision.json');
  final stable = object('tool/stable_readiness_decision.json');
  final distribution = object('tool/rc_distribution_authorization.json');
  if (rc['state'] != 'NOT_READY_FOR_1_0_RC' ||
      stable['state'] != 'NOT_READY_FOR_1_0' ||
      distribution['state'] != 'NOT_AUTHORIZED') {
    errors.add('Existing release authorities are not fail-closed.');
  }
  final encodedRc = jsonEncode(rc);
  if (encodedRc.contains('deferred to RC.3') ||
      encodedRc.contains(
        'known OwnedRuntimeSlot.replaceGraph semantic defect',
      )) {
    errors.add(
      'The fixed replacement finding remains a stale release blocker.',
    );
  }
  final optional = object('tool/optional_slice_gate.json');
  final slices = optional['slices'];
  if (slices is! List<Object?> ||
      slices.length != 5 ||
      slices.any(
        (value) =>
            value is! Map<String, Object?> || value['status'] != 'DEFERRED',
      )) {
    errors.add('Optional slices are not explicitly deferred.');
  }
  final ledger = File('${root.path}/docs/work/technical-hardening-ledger.adoc')
      .readAsStringSync();
  for (var index = 1; index <= 10; index += 1) {
    final id = 'DRT-P0-${index.toString().padLeft(3, '0')}';
    final start = ledger.indexOf('|`$id`');
    if (start < 0 ||
        !ledger
            .substring(start, (start + 80).clamp(0, ledger.length))
            .contains('|`FIXED`')) {
      errors.add('$id is not FIXED in the hardening ledger.');
    }
  }
  final p1 = ledger.indexOf('|`DRT-P1-001`');
  if (p1 < 0 ||
      !ledger
          .substring(p1, (p1 + 80).clamp(0, ledger.length))
          .contains('|`FIXED`')) {
    errors.add('DRT-P1-001 is not FIXED in the hardening ledger.');
  }

  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Technical hardening readiness is fail-closed: local goals implemented, '
    'optional slices deferred, release NOT READY pending exact-SHA evidence.',
  );
}
