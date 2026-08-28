import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';

/// Validates the neutral ledger, workspace review, and Analyzer snapshot.
Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final decoded = jsonDecode(
    await File('${root.path}/tool/ecosystem_policy.json').readAsString(),
  );
  if (decoded is! Map<String, Object?>) {
    stderr.writeln('Ecosystem policy must be a JSON object.');
    exitCode = 1;
    return;
  }
  final errors = <String>[];
  EcosystemPolicy policy;
  try {
    policy = EcosystemPolicy.fromJson(decoded);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
    return;
  }
  if (policy.validationFindings.isNotEmpty) {
    errors.add('The global ledger contains invalid policy entries.');
  }
  if (policy.exceptions.isNotEmpty) {
    errors.add('Consumer exceptions are forbidden in the global ledger.');
  }
  final auditDate = DateTime.tryParse('${decoded['auditDate']}T00:00:00Z');
  if (auditDate == null) errors.add('The policy audit date is invalid.');

  final boundary = jsonDecode(
    await File('${root.path}/tool/boundary_policy.json').readAsString(),
  ) as Map<String, Object?>;
  final universal = (boundary['forbiddenPackages']! as List<Object?>)
      .cast<String>()
      .toSet();
  final sourceBlocking = policy.records.values
      .where(
        (record) =>
            record.decision == EcosystemDecision.prohibitedNativeStrict ||
            record.decision == EcosystemDecision.overlapWarning,
      )
      .map((record) => record.package)
      .toSet();
  if (sourceBlocking.length != universal.length ||
      !sourceBlocking.containsAll(universal)) {
    errors.add(
      'Installed overlap plus global prohibitions must equal the source-level '
      'architecture package set.',
    );
  }
  for (final package in const <String>{
    'app_tracking_transparency',
    'brasil_fields',
    'dart_polylabel2',
    'flutter_native_splash',
    'freezed',
    'gal',
    'retrofit',
    'sentry_dio',
    'uuid',
  }) {
    if (policy.records[package]?.decision !=
        EcosystemDecision.advisoryAlternative) {
      errors.add('$package must remain an informational alternative.');
    }
  }
  final listen = policy.records['listen'];
  if (listen?.decision != EcosystemDecision.approvedPrimitive ||
      listen?.boundary != 'pure_dart_primitive' ||
      listen?.maturity != 'reviewed' ||
      listen?.compatibility == null ||
      listen?.adoptionStatus != 'deferred_until_real_consumer') {
    errors.add(
      'listen must remain an approved primitive deferred until a real '
      'pure-Dart consumer exists.',
    );
  }
  for (final record in policy.records.values) {
    if ((record.decision == EcosystemDecision.advisoryAlternative ||
            record.decision == EcosystemDecision.prohibitedNativeStrict ||
            record.decision == EcosystemDecision.overlapWarning) &&
        (record.replacement == null || record.replacement!.trim().isEmpty)) {
      errors.add('${record.package} requires a documented alternative.');
    }
    final bundled = EcosystemPolicy.bundled.explain(record.package);
    if (bundled.decision != record.decision ||
        bundled.boundary != record.boundary ||
        bundled.maturity != record.maturity ||
        bundled.adoptionStatus != record.adoptionStatus ||
        bundled.replacement != record.replacement ||
        !_sameStrings(bundled.conflictsWith, record.conflictsWith)) {
      errors.add('${record.package} is stale in the bundled CLI policy.');
    }
  }

  final resolved = jsonDecode(
    await File('${root.path}/.dart_tool/package_graph.json').readAsString(),
  ) as Map<String, Object?>;
  final resolvedNames = <String>{
    for (final raw in resolved['packages']! as List<Object?>)
      (raw! as Map<String, Object?>)['name']! as String,
  };
  if (resolvedNames.length != policy.workspaceReviewedPackages.length ||
      !policy.workspaceReviewedPackages.containsAll(resolvedNames)) {
    final missing = resolvedNames.difference(policy.workspaceReviewedPackages)
      ..removeAll(policy.records.keys);
    final stale = policy.workspaceReviewedPackages.difference(resolvedNames);
    errors.add(
      'Workspace review inventory is stale; missing=$missing, stale=$stale.',
    );
  }
  final releaseAudit = await EcosystemDependencyAuditor(
    root,
    policy,
    blockUnreviewed: true,
  ).audit();
  if (!releaseAudit.isClean) {
    errors.add(
      'Dartitect workspace ecosystem audit failed: '
      '${releaseAudit.findings.map((finding) => finding.package).toSet()}.',
    );
  }

  final snapshot = await File(
    '${root.path}/packages/dartitect_lints/lib/src/ecosystem_policy.g.dart',
  ).readAsString();
  if (!snapshot.contains('// Source: tool/ecosystem_policy.json (schema 3).')) {
    errors.add('Analyzer ecosystem snapshot has an obsolete schema marker.');
  }
  for (final record in policy.records.values) {
    final marker = "'${record.package}':";
    final start = snapshot.indexOf(marker);
    if (start < 0) {
      errors.add('Analyzer policy snapshot is missing ${record.package}.');
      continue;
    }
    final next = snapshot.indexOf("\n  '", start + marker.length);
    final block = snapshot.substring(start, next < 0 ? snapshot.length : next);
    final normalizedBlock = block.replaceAll(RegExp(r'\s+'), ' ');
    final decision = 'DartitectEcosystemDecision.${record.decision.name}';
    final acceptedAlias =
        record.decision == EcosystemDecision.approved &&
            block.contains('_approved') ||
        record.decision == EcosystemDecision.approvedPrimitive &&
            block.contains('_approvedPrimitive') ||
        record.decision == EcosystemDecision.reviewedException &&
            block.contains('_reviewed');
    if (!block.contains(decision) && !acceptedAlias) {
      errors.add('Analyzer decision is stale for ${record.package}.');
    }
    if (record.replacement case final replacement?) {
      if (!normalizedBlock.contains("replacement: '$replacement'")) {
        errors.add('Analyzer alternative is stale for ${record.package}.');
      }
    }
    for (final conflict in record.conflictsWith) {
      if (!block.contains("'$conflict'")) {
        errors.add('Analyzer conflict is stale for ${record.package}.');
      }
    }
  }
  if (!snapshot.contains('.dartitect') ||
      !snapshot.contains('ecosystem-policy.json')) {
    errors.add('Analyzer snapshot does not load consumer-owned overlays.');
  }

  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Neutral ecosystem policy passed: ${policy.records.length} global '
    'decisions, ${resolvedNames.length} reviewed workspace packages, and no '
    'global consumer exceptions.',
  );
}

bool _sameStrings(List<String> left, List<String> right) =>
    left.length == right.length &&
    left.toSet().containsAll(right) &&
    right.toSet().containsAll(left);
