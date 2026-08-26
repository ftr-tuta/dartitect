import 'dart:convert';
import 'dart:io';

const _schemaStatuses = <String>{
  'PLANNED',
  'IN_PROGRESS',
  'BLOCKED',
  'IMPLEMENTED_LOCAL',
  'EXTERNAL_REQUIRED',
  'COMPLETE',
  'CANCELLED',
};
final _sha = RegExp(r'^[0-9a-f]{40}$');
final _sha256 = RegExp(r'^[0-9a-f]{64}$');

Future<void> main(List<String> arguments) async {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final gateFile = _gateFile(root, arguments);
  final validation = await _validate(root, gateFile);
  if (validation.errors.isNotEmpty) {
    stderr.writeln(validation.errors.join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Goal gate authority ${validation.roadmap} passed with '
    '${validation.goalCount} topologically valid goals; release status is '
    '${validation.releaseStatus}.',
  );
}

File _gateFile(Directory root, List<String> arguments) {
  if (arguments.length > 1 ||
      (arguments.isNotEmpty && !arguments.single.startsWith('--file='))) {
    throw ArgumentError('Usage: check_goal_gates.dart [--file=<path>]');
  }
  if (arguments.isEmpty) return File('${root.path}/tool/goal_gates.json');
  return File(arguments.single.substring('--file='.length)).absolute;
}

Future<_Validation> _validate(Directory root, File gateFile) async {
  final errors = <String>[];
  Object? decoded;
  try {
    decoded = jsonDecode(await gateFile.readAsString());
  } on Object catch (error) {
    return _Validation(
      errors: <String>['Goal gate file is not valid JSON: $error'],
    );
  }
  if (decoded is! Map<String, Object?> || decoded['schemaVersion'] != 7) {
    return _Validation(errors: <String>['Unsupported Goal gate schema.']);
  }

  final roadmap = decoded['roadmap'];
  String? roadmapId;
  List<String>? requiredGoalIds;
  if (roadmap is! Map<String, Object?> ||
      roadmap['id'] is! String ||
      (roadmap['id']! as String).trim().isEmpty ||
      roadmap['status'] != 'active' ||
      !_stringList(roadmap['requiredGoalIds'], nonEmpty: true)) {
    errors.add('The active roadmap descriptor is invalid.');
  } else {
    roadmapId = roadmap['id']! as String;
    requiredGoalIds = (roadmap['requiredGoalIds']! as List<Object?>)
        .cast<String>();
    if (requiredGoalIds.toSet().length != requiredGoalIds.length) {
      errors.add('The active roadmap contains duplicate required goal IDs.');
    }
  }

  final releaseStatus = decoded['releaseStatus'];
  if (releaseStatus is! String || releaseStatus.trim().isEmpty) {
    errors.add('releaseStatus must be a non-empty recorded decision.');
  }
  if (decoded['featurePolicy'] is! String ||
      (decoded['featurePolicy']! as String).trim().isEmpty) {
    errors.add('featurePolicy must be a non-empty policy name.');
  }
  final statusPolicy = _validateStatusPolicy(decoded['statusPolicy'], errors);
  await _validateTarget(root, decoded['target'], errors);
  await _validateBaselines(root, decoded['baselines'], errors);

  final rawGoals = decoded['goals'];
  if (rawGoals is! List<Object?>) {
    errors.add('Goal gate list is missing.');
    return _Validation(
      errors: errors,
      roadmap: roadmapId,
      releaseStatus: releaseStatus as String?,
    );
  }

  final goals = <String, _Goal>{};
  final order = <String>[];
  for (final raw in rawGoals) {
    final goal = await _parseGoal(root, raw, errors);
    if (goal == null) continue;
    if (goals.containsKey(goal.id)) {
      errors.add('Duplicate goal: ${goal.id}.');
      continue;
    }
    goals[goal.id] = goal;
    order.add(goal.id);
  }

  final required = requiredGoalIds?.toSet() ?? const <String>{};
  final missing = required.difference(goals.keys.toSet()).toList()..sort();
  if (missing.isNotEmpty) errors.add('Required goals are missing: $missing.');
  for (final goal in goals.values) {
    if (required.contains(goal.id) != goal.required) {
      errors.add(
        '${goal.id} required flag disagrees with roadmap.requiredGoalIds.',
      );
    }
  }

  final positions = <String, int>{
    for (var index = 0; index < order.length; index += 1) order[index]: index,
  };
  for (final goal in goals.values) {
    for (final dependency in goal.dependsOn) {
      if (!goals.containsKey(dependency)) {
        errors.add('${goal.id} depends on unknown goal $dependency.');
      } else if (positions[dependency]! >= positions[goal.id]!) {
        errors.add('Goal order is not topological: $dependency -> ${goal.id}.');
      }
    }
  }
  _validateAcyclic(goals, errors);
  _validateStatuses(goals, statusPolicy.reviewAuthorities, errors);
  await _validateReopening(root, goals, statusPolicy.receiptOnlyPaths, errors);

  return _Validation(
    errors: errors,
    roadmap: roadmapId,
    releaseStatus: releaseStatus as String?,
    goalCount: goals.length,
  );
}

_StatusPolicy _validateStatusPolicy(Object? raw, List<String> errors) {
  if (raw is! Map<String, Object?> ||
      !_stringList(raw['allowed'], nonEmpty: true) ||
      raw['localEvidenceMaximum'] != 'IMPLEMENTED_LOCAL' ||
      !_stringList(raw['receiptOnlyPaths'], nonEmpty: true) ||
      !_validReviewAuthority(raw['reviewAuthority'])) {
    errors.add('Goal status policy is invalid.');
    return const _StatusPolicy();
  }
  final allowed = (raw['allowed']! as List<Object?>).cast<String>().toSet();
  if (allowed.length != _schemaStatuses.length ||
      !allowed.containsAll(_schemaStatuses)) {
    errors.add('Goal status policy must contain only the schema statuses.');
  }
  final receiptOnlyPaths = (raw['receiptOnlyPaths']! as List<Object?>)
      .cast<String>();
  if (receiptOnlyPaths.toSet().length != receiptOnlyPaths.length ||
      receiptOnlyPaths.any((path) => !_safeReceiptPath(path))) {
    errors.add('Goal receipt-only paths must be unique exact safe paths.');
  }
  final reviewAuthority = raw['reviewAuthority']! as Map<String, Object?>;
  return _StatusPolicy(
    receiptOnlyPaths: receiptOnlyPaths.toSet(),
    reviewAuthorities: <String>{reviewAuthority['name']! as String},
  );
}

Future<void> _validateTarget(
  Directory root,
  Object? raw,
  List<String> errors,
) async {
  if (raw is! Map<String, Object?> ||
      raw['packageCount'] is! int ||
      raw['entrypointCount'] is! int) {
    errors.add('Target topology is invalid.');
    return;
  }
  final packageCount = await Directory('${root.path}/packages')
      .list(followLinks: false)
      .where((entity) => entity is Directory)
      .length;
  Object? snapshot;
  try {
    snapshot = jsonDecode(
      await File('${root.path}/tool/api_surface.snapshot.json').readAsString(),
    );
  } on Object {
    errors.add('The checked API snapshot is not readable.');
    return;
  }
  final entrypoints = snapshot is Map<String, Object?>
      ? snapshot['entrypoints']
      : null;
  if (packageCount != raw['packageCount'] ||
      entrypoints is! Map<String, Object?> ||
      entrypoints.length != raw['entrypointCount']) {
    errors.add(
      'Target topology does not match the checked package/API inventory.',
    );
  }
}

Future<void> _validateBaselines(
  Directory root,
  Object? raw,
  List<String> errors,
) async {
  if (raw is! Map<String, Object?> ||
      !raw.containsKey('implementation') ||
      !raw.containsKey('stabilization') ||
      !raw.containsKey('rcCandidates') ||
      !raw.containsKey('stableCandidate')) {
    errors.add('The candidate baseline registry is incomplete.');
    return;
  }
  for (final entry in raw.entries) {
    final value = entry.value;
    if (value == null) continue;
    if (entry.key == 'rcCandidates') {
      if (value is! List<Object?>) {
        errors.add('rcCandidates must be a list.');
        continue;
      }
      for (var index = 0; index < value.length; index += 1) {
        await _validateBaseline(
          root,
          value[index],
          'rcCandidates[$index]',
          errors,
        );
      }
      continue;
    }
    await _validateBaseline(root, value, entry.key, errors);
  }
}

Future<void> _validateBaseline(
  Directory root,
  Object? raw,
  String name,
  List<String> errors,
) async {
  if (raw is! Map<String, Object?> ||
      raw['sha'] is! String ||
      !_sha.hasMatch(raw['sha']! as String) ||
      raw['tree'] is! String ||
      !_sha.hasMatch(raw['tree']! as String) ||
      !_utcTimestamp(raw['recordedAt']) ||
      raw['sdks'] is! Map<String, Object?> ||
      (raw['sdks']! as Map<String, Object?>).isEmpty ||
      raw['inventory'] is! Map<String, Object?> ||
      raw['workflowRuns'] is! List<Object?>) {
    errors.add('Baseline $name is incomplete.');
    return;
  }
  if ((raw['sdks']! as Map<String, Object?>).values.any(
    (value) => value is! String || value.trim().isEmpty,
  )) {
    errors.add('Baseline $name contains an invalid SDK receipt.');
  }
  final sha = raw['sha']! as String;
  final tree = await _git(root, <String>['show', '-s', '--format=%T', sha]);
  if (tree == null) {
    errors.add('Baseline $name tree cannot be reproduced.');
    return;
  }
  if (tree.trim() != raw['tree']) {
    errors.add('Baseline $name tree cannot be reproduced.');
    return;
  }
  final inventory = raw['inventory']! as Map<String, Object?>;
  final packageCount = inventory['packageCount'];
  final entrypointCount = inventory['entrypointCount'];
  if (packageCount is! int || entrypointCount is! int) {
    errors.add('Baseline $name inventory is invalid.');
  } else {
    final packageTree = await _git(root, <String>[
      'ls-tree',
      '--name-only',
      '$sha:packages',
    ]);
    final snapshotText = await _git(root, <String>[
      'show',
      '$sha:tool/api_surface.snapshot.json',
    ]);
    if (packageTree == null || snapshotText == null) {
      errors.add('Baseline $name inventory cannot be reproduced.');
    } else {
      final packages = const LineSplitter()
          .convert(packageTree)
          .where((line) => line.isNotEmpty)
          .length;
      final snapshot = jsonDecode(snapshotText) as Map<String, Object?>;
      final entrypoints = snapshot['entrypoints'];
      if (packages != packageCount ||
          entrypoints is! Map<String, Object?> ||
          entrypoints.length != entrypointCount) {
        errors.add('Baseline $name inventory does not match its commit.');
      }
    }
  }
  for (final run in raw['workflowRuns']! as List<Object?>) {
    if (!_validWorkflowRun(run, expectedSha: sha)) {
      errors.add('Baseline $name contains an invalid same-SHA workflow run.');
    }
  }
}

Future<_Goal?> _parseGoal(
  Directory root,
  Object? raw,
  List<String> errors,
) async {
  if (raw is! Map<String, Object?>) {
    errors.add('Invalid goal entry: $raw.');
    return null;
  }
  final id = raw['id'];
  final status = raw['status'];
  final sourceSha = raw['sourceSha'];
  if (id is! String ||
      id.trim().isEmpty ||
      raw['required'] is! bool ||
      status is! String ||
      !_schemaStatuses.contains(status) ||
      !_stringList(raw['dependsOn']) ||
      raw['owner'] is! String ||
      (raw['owner']! as String).trim().isEmpty ||
      !_stringList(raw['affectedPackages']) ||
      !_stringList(raw['coveredPaths'], nonEmpty: true) ||
      !_stringList(raw['acceptance'], nonEmpty: true) ||
      !_stringList(raw['gateCommands'], nonEmpty: true) ||
      !_stringList(raw['evidence']) ||
      sourceSha != null &&
          (sourceSha is! String || !_sha.hasMatch(sourceSha)) ||
      raw['workflowRuns'] is! List<Object?> ||
      raw['artifactDigests'] is! List<Object?> ||
      !_stringList(raw['reviewedBy']) ||
      raw['completedAt'] != null && !_utcTimestamp(raw['completedAt'])) {
    errors.add('Goal entry is incomplete or invalid: ${id ?? '<unknown>'}.');
    return null;
  }
  final dependencies = (raw['dependsOn']! as List<Object?>).cast<String>();
  if (dependencies.toSet().length != dependencies.length ||
      dependencies.contains(id)) {
    errors.add('Goal $id has duplicate or self dependencies.');
  }
  for (final package
      in (raw['affectedPackages']! as List<Object?>).cast<String>()) {
    if (!await Directory('${root.path}/packages/$package').exists()) {
      errors.add('Goal $id references missing affected package $package.');
    }
  }
  final coveredPaths = (raw['coveredPaths']! as List<Object?>).cast<String>();
  for (final path in coveredPaths) {
    if (!_safePattern(path))
      errors.add('Goal $id has unsafe covered path $path.');
  }
  final evidence = (raw['evidence']! as List<Object?>).cast<String>();
  if (status != 'PLANNED') {
    for (final path in evidence) {
      if (!path.contains('://') && !await File('${root.path}/$path').exists()) {
        errors.add('Goal $id references missing evidence: $path.');
      }
    }
  }
  final workflowRuns = raw['workflowRuns']! as List<Object?>;
  for (final run in workflowRuns) {
    if (!_validWorkflowRun(run, expectedSha: sourceSha as String?)) {
      errors.add('Goal $id contains an invalid or cross-SHA workflow run.');
    }
  }
  for (final artifact in raw['artifactDigests']! as List<Object?>) {
    if (artifact is! Map<String, Object?> ||
        artifact['path'] is! String ||
        (artifact['path']! as String).trim().isEmpty ||
        artifact['sha256'] is! String ||
        !_sha256.hasMatch(artifact['sha256']! as String) ||
        artifact['sourceSha'] != sourceSha) {
      errors.add('Goal $id contains an invalid or cross-SHA artifact digest.');
    }
  }
  return _Goal(
    id: id,
    required: raw['required']! as bool,
    status: status,
    dependsOn: dependencies,
    coveredPaths: coveredPaths,
    evidence: evidence,
    sourceSha: sourceSha as String?,
    workflowRuns: workflowRuns,
    reviewedBy: (raw['reviewedBy']! as List<Object?>).cast<String>(),
    completedAt: raw['completedAt'] as String?,
    cancellation: raw['cancellation'],
  );
}

void _validateAcyclic(Map<String, _Goal> goals, List<String> errors) {
  final visiting = <String>{};
  final visited = <String>{};
  bool visit(String id) {
    if (visited.contains(id)) return true;
    if (!visiting.add(id)) return false;
    for (final dependency in goals[id]?.dependsOn ?? const <String>[]) {
      if (goals.containsKey(dependency) && !visit(dependency)) return false;
    }
    visiting.remove(id);
    visited.add(id);
    return true;
  }

  for (final id in goals.keys) {
    if (!visit(id)) {
      errors.add('Goal DAG contains a cycle involving $id.');
      return;
    }
  }
}

void _validateStatuses(
  Map<String, _Goal> goals,
  Set<String> reviewAuthorities,
  List<String> errors,
) {
  for (final goal in goals.values) {
    if (goal.status == 'CANCELLED') {
      if (goal.required) {
        errors.add('Required goal ${goal.id} cannot be CANCELLED.');
      }
      if (!_validCancellation(goal.cancellation)) {
        errors.add(
          'Cancelled goal ${goal.id} lacks authority-reviewed rationale.',
        );
      } else {
        final cancellation = goal.cancellation! as Map<String, Object?>;
        final reviewers = (cancellation['reviewedBy']! as List<Object?>)
            .cast<String>();
        if (reviewers.any(
          (reviewer) => !reviewAuthorities.contains(reviewer),
        )) {
          errors.add('${goal.id} cancellation has an unauthorized reviewer.');
        }
      }
    }
    final cancelledOptional = <String>[];
    final incompleteRequired = <String>[];
    for (final dependencyId in goal.dependsOn) {
      final dependency = goals[dependencyId];
      if (dependency == null) continue;
      if (dependency.status == 'CANCELLED' && !dependency.required) {
        cancelledOptional.add(dependencyId);
      } else if (dependency.status != 'COMPLETE' && dependency.required) {
        incompleteRequired.add(dependencyId);
      }
    }
    if (cancelledOptional.length > 1) {
      errors.add(
        '${goal.id} accepts more than one cancelled optional predecessor.',
      );
    }
    if (goal.status == 'COMPLETE') {
      if (incompleteRequired.isNotEmpty) {
        errors.add(
          '${goal.id} cannot be COMPLETE before required predecessors: '
          '$incompleteRequired.',
        );
      }
      if (goal.sourceSha == null ||
          goal.evidence.isEmpty ||
          goal.workflowRuns.isEmpty ||
          goal.reviewedBy.isEmpty ||
          goal.completedAt == null) {
        errors.add(
          '${goal.id} COMPLETE requires same-SHA remote evidence and recorded review.',
        );
      }
      if (goal.reviewedBy.any(
        (reviewer) => !reviewAuthorities.contains(reviewer),
      )) {
        errors.add('${goal.id} contains an unauthorized reviewer.');
      }
    }
    // EXTERNAL_REQUIRED is a fail-closed waiting state, not a completion
    // claim. COMPLETE above remains the only state that requires every
    // predecessor to be complete.
  }
}

Future<void> _validateReopening(
  Directory root,
  Map<String, _Goal> goals,
  Set<String> receiptOnlyPaths,
  List<String> errors,
) async {
  final changedGoals = <String>{};
  for (final goal in goals.values.where((goal) => goal.status == 'COMPLETE')) {
    final changed = await _git(root, <String>[
      'diff',
      '--name-only',
      goal.sourceSha!,
      '--',
    ]);
    if (changed == null) {
      errors.add('${goal.id} sourceSha cannot be compared for reopening.');
      continue;
    }
    final untracked = await _git(root, const <String>[
      'ls-files',
      '--others',
      '--exclude-standard',
    ]);
    final paths = const LineSplitter()
        .convert('$changed\n${untracked ?? ''}')
        .where((path) => path.isNotEmpty && !receiptOnlyPaths.contains(path));
    if (paths.any(
      (path) => goal.coveredPaths.any((pattern) => _globMatches(pattern, path)),
    )) {
      changedGoals.add(goal.id);
      errors.add('${goal.id} must reopen because a covered path changed.');
    }
  }
  if (changedGoals.isEmpty) return;
  final impacted = <String>{...changedGoals};
  var added = true;
  while (added) {
    added = false;
    for (final goal in goals.values) {
      if (!impacted.contains(goal.id) &&
          goal.dependsOn.any(impacted.contains)) {
        impacted.add(goal.id);
        added = true;
      }
    }
  }
  for (final id in impacted.difference(changedGoals)) {
    if (goals[id]?.status == 'COMPLETE') {
      errors.add('$id must reopen as part of the reverse dependency closure.');
    }
  }
}

bool _validWorkflowRun(Object? raw, {required String? expectedSha}) =>
    raw is Map<String, Object?> &&
    raw['workflow'] is String &&
    (raw['workflow']! as String).trim().isNotEmpty &&
    raw['runId'] is int &&
    (raw['runId']! as int) > 0 &&
    raw['url'] is String &&
    Uri.tryParse(raw['url']! as String)?.hasAbsolutePath == true &&
    raw['sourceSha'] is String &&
    _sha.hasMatch(raw['sourceSha']! as String) &&
    (expectedSha == null || raw['sourceSha'] == expectedSha) &&
    raw['conclusion'] == 'success';

bool _validCancellation(Object? raw) =>
    raw is Map<String, Object?> &&
    raw['justification'] is String &&
    (raw['justification']! as String).trim().isNotEmpty &&
    raw['owner'] is String &&
    (raw['owner']! as String).trim().isNotEmpty &&
    _stringList(raw['reviewedBy'], nonEmpty: true);

bool _validReviewAuthority(Object? raw) =>
    raw is Map<String, Object?> &&
    raw['kind'] == 'MAINTAINER_DELEGATED_AUTOMATION' &&
    raw['name'] is String &&
    (raw['name']! as String).trim().isNotEmpty &&
    raw['authorizedBy'] is String &&
    (raw['authorizedBy']! as String).trim().isNotEmpty &&
    _utcTimestamp(raw['authorizedAt']) &&
    raw['scope'] is String &&
    (raw['scope']! as String).trim().isNotEmpty;

bool _stringList(Object? raw, {bool nonEmpty = false}) =>
    raw is List<Object?> &&
    (!nonEmpty || raw.isNotEmpty) &&
    raw.every((value) => value is String && value.trim().isNotEmpty);

bool _utcTimestamp(Object? raw) {
  if (raw is! String || !raw.endsWith('Z')) return false;
  return DateTime.tryParse(raw)?.isUtc == true;
}

bool _safePattern(String pattern) {
  final normalized = pattern.replaceAll('\\', '/');
  return normalized == pattern &&
      normalized.isNotEmpty &&
      normalized != '*' &&
      normalized != '**' &&
      normalized != '**/*' &&
      !normalized.startsWith('/') &&
      !normalized.split('/').contains('..');
}

bool _safeReceiptPath(String path) =>
    _safePattern(path) && !path.contains('*') && !path.contains('?');

bool _globMatches(String glob, String path) {
  final pattern = StringBuffer('^');
  for (var index = 0; index < glob.length; index += 1) {
    final character = glob[index];
    if (character == '*' && index + 1 < glob.length && glob[index + 1] == '*') {
      pattern.write('.*');
      index += 1;
    } else if (character == '*') {
      pattern.write('[^/]*');
    } else if (character == '?') {
      pattern.write('[^/]');
    } else {
      pattern.write(RegExp.escape(character));
    }
  }
  pattern.write(r'$');
  return RegExp(pattern.toString()).hasMatch(path);
}

Future<String?> _git(Directory root, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: root.path,
  );
  return result.exitCode == 0 ? result.stdout as String : null;
}

final class _Goal {
  const _Goal({
    required this.id,
    required this.required,
    required this.status,
    required this.dependsOn,
    required this.coveredPaths,
    required this.evidence,
    required this.sourceSha,
    required this.workflowRuns,
    required this.reviewedBy,
    required this.completedAt,
    required this.cancellation,
  });

  final String id;
  final bool required;
  final String status;
  final List<String> dependsOn;
  final List<String> coveredPaths;
  final List<String> evidence;
  final String? sourceSha;
  final List<Object?> workflowRuns;
  final List<String> reviewedBy;
  final String? completedAt;
  final Object? cancellation;
}

final class _StatusPolicy {
  const _StatusPolicy({
    this.receiptOnlyPaths = const <String>{},
    this.reviewAuthorities = const <String>{},
  });

  final Set<String> receiptOnlyPaths;
  final Set<String> reviewAuthorities;
}

final class _Validation {
  const _Validation({
    required this.errors,
    this.roadmap,
    this.releaseStatus,
    this.goalCount = 0,
  });

  final List<String> errors;
  final String? roadmap;
  final String? releaseStatus;
  final int goalCount;
}
