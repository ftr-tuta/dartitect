import 'dart:convert';
import 'dart:io';

/// Stable ecosystem disposition from the versioned offline ledger.
enum EcosystemDecision {
  /// Approved behind its documented boundary.
  approved,

  /// A reviewed low-level primitive, without authorizing framework adoption.
  approvedPrimitive,

  /// An equivalent Dartitect capability exists, without prohibiting this one.
  advisoryAlternative,

  /// Allowed only by a scoped, owned, non-expired consumer overlay.
  reviewedException,

  /// Universally forbidden in the Native Strict profile.
  prohibitedNativeStrict,

  /// Package is not present in the audited ledger.
  unreviewed,
}

/// One normalized package decision.
final class EcosystemPolicyRecord {
  /// Creates a record parsed from the offline ledger.
  const EcosystemPolicyRecord({
    required this.package,
    required this.decision,
    required this.boundary,
    required this.maturity,
    required this.adoptionStatus,
    required this.owner,
    required this.documentation,
    this.replacement,
    this.publisher,
    this.repository,
    this.compatibility,
    this.conflictsWith = const <String>[],
  });

  /// pub package name.
  final String package;

  /// Audited disposition.
  final EcosystemDecision decision;

  /// Architectural boundary at which the package was reviewed.
  final String boundary;

  /// Review or release maturity, independent from architectural permission.
  final String maturity;

  /// Current Dartitect adoption status, independent from compatibility.
  final String adoptionStatus;

  /// Accountable maintainer or upstream authority.
  final String owner;

  /// Versioned policy documentation.
  final String documentation;

  /// Dartitect alternative or required architectural replacement.
  final String? replacement;

  /// Verified publisher domain when available.
  final String? publisher;

  /// Audited repository URL when available.
  final String? repository;

  /// Compatibility constraint or audit note.
  final String? compatibility;

  /// Resolved packages that make this otherwise advisory choice a duplicate.
  final List<String> conflictsWith;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'package': package,
    'decision': _decisionName(decision),
    'boundary': boundary,
    'maturity': maturity,
    'adoptionStatus': adoptionStatus,
    'owner': owner,
    'documentation': documentation,
    if (replacement != null) 'replacement': replacement,
    if (publisher != null) 'publisher': publisher,
    if (repository != null) 'repository': repository,
    if (compatibility != null) 'compatibility': compatibility,
    if (conflictsWith.isNotEmpty) 'conflictsWith': conflictsWith,
  };
}

/// Scoped consumer policy attached to one reviewed package.
final class EcosystemPolicyException {
  /// Creates a parsed exception or overlay scope.
  const EcosystemPolicyException({
    required this.package,
    required this.owner,
    required this.reason,
    required this.expiresOn,
    required this.paths,
    this.directOwners = const <String>[],
  });

  /// Package receiving the scoped decision.
  final String package;

  /// Accountable consumer owner.
  final String owner;

  /// Non-empty business or technical reason.
  final String reason;

  /// Last accepted UTC calendar date.
  final DateTime expiresOn;

  /// Non-global consumer paths.
  final List<String> paths;

  /// Direct dependencies allowed to own this package transitively.
  final List<String> directOwners;

  /// Whether the scope has expired at [now].
  bool isExpiredAt(DateTime now) {
    final today = DateTime.utc(now.year, now.month, now.day);
    return today.isAfter(expiresOn);
  }

  bool _acceptsOwner(String owner) =>
      directOwners.isEmpty || directOwners.contains(owner);
}

final class _OverlayRecord {
  const _OverlayRecord(this.record, this.scope);

  final EcosystemPolicyRecord record;
  final EcosystemPolicyException scope;
}

/// Validated, offline ecosystem policy shared by CLI and scanner.
final class EcosystemPolicy {
  const EcosystemPolicy._({
    required this.profile,
    required this.documentation,
    required this.records,
    required this.exceptions,
    required this.workspaceReviewedPackages,
    required this.validationFindings,
    required Map<String, List<_OverlayRecord>> overlays,
  }) : _overlays = overlays;

  /// Parses the neutral schema-v3 global ledger.
  factory EcosystemPolicy.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != 3 ||
        json['profile'] is! String ||
        json['documentation'] is! String ||
        json['decisions'] is! Map<String, Object?> ||
        json['workspaceReviewedPackages'] is! List<Object?> ||
        json['exceptions'] is! List<Object?>) {
      throw const FormatException('Unsupported ecosystem policy schema.');
    }
    final documentation = json['documentation']! as String;
    final records = <String, EcosystemPolicyRecord>{};
    for (final entry in (json['decisions']! as Map<String, Object?>).entries) {
      final value = entry.value;
      if (!_packageName.hasMatch(entry.key) || value is! Map<String, Object?>) {
        throw const FormatException('Invalid ecosystem policy decision.');
      }
      records[entry.key] = _parseRecord(
        entry.key,
        value,
        documentation: documentation,
      );
    }
    final reviewed = <String>{};
    for (final value in json['workspaceReviewedPackages']! as List<Object?>) {
      if (value is! String ||
          !_packageName.hasMatch(value) ||
          !reviewed.add(value)) {
        throw const FormatException(
          'Invalid reviewed workspace package inventory.',
        );
      }
    }

    final exceptions = <EcosystemPolicyException>[];
    final validation = <EcosystemAuditFinding>[];
    for (final value in json['exceptions']! as List<Object?>) {
      final parsed = _parseException(value);
      if (parsed == null) {
        validation.add(_invalidOverlayFinding());
      } else {
        exceptions.add(parsed);
      }
    }
    return EcosystemPolicy._(
      profile: json['profile']! as String,
      documentation: documentation,
      records: Map<String, EcosystemPolicyRecord>.unmodifiable(records),
      exceptions: List<EcosystemPolicyException>.unmodifiable(exceptions),
      workspaceReviewedPackages: Set<String>.unmodifiable(reviewed),
      validationFindings: List<EcosystemAuditFinding>.unmodifiable(validation),
      overlays: const <String, List<_OverlayRecord>>{},
    );
  }

  /// Applies a consumer-owned `.dartitect/ecosystem-policy.json` overlay.
  factory EcosystemPolicy.withOverlay(
    EcosystemPolicy global,
    Map<String, Object?> json,
  ) {
    if (json['schemaVersion'] != 1 || json['entries'] is! List<Object?>) {
      throw const FormatException('Unsupported ecosystem overlay schema.');
    }
    final overlays = <String, List<_OverlayRecord>>{
      for (final entry in global._overlays.entries)
        entry.key: <_OverlayRecord>[...entry.value],
    };
    final validation = <EcosystemAuditFinding>[...global.validationFindings];
    final exceptions = <EcosystemPolicyException>[...global.exceptions];
    for (final raw in json['entries']! as List<Object?>) {
      if (raw is! Map<String, Object?> || raw['package'] is! String) {
        validation.add(_invalidOverlayFinding());
        continue;
      }
      final package = raw['package']! as String;
      final scope = _parseException(raw);
      EcosystemPolicyRecord? record;
      try {
        record = _parseRecord(
          package,
          raw,
          documentation: '.dartitect/ecosystem-policy.json',
          overlay: true,
        );
      } on FormatException {
        // Reported below through one stable payload-free diagnostic.
        record = null;
      }
      final base = global.explain(package);
      if (scope == null ||
          record == null ||
          base.decision == EcosystemDecision.prohibitedNativeStrict) {
        validation.add(_invalidOverlayFinding(package));
        continue;
      }
      exceptions.add(scope);
      overlays
          .putIfAbsent(package, () => <_OverlayRecord>[])
          .add(_OverlayRecord(record, scope));
    }
    return EcosystemPolicy._(
      profile: global.profile,
      documentation: global.documentation,
      records: global.records,
      exceptions: List<EcosystemPolicyException>.unmodifiable(exceptions),
      workspaceReviewedPackages: global.workspaceReviewedPackages,
      validationFindings: List<EcosystemAuditFinding>.unmodifiable(validation),
      overlays: Map<String, List<_OverlayRecord>>.unmodifiable(
        <String, List<_OverlayRecord>>{
          for (final entry in overlays.entries)
            entry.key: List<_OverlayRecord>.unmodifiable(entry.value),
        },
      ),
    );
  }

  /// Loads the nearest global ledger plus nearest consumer overlay.
  static Future<EcosystemPolicy> load(Directory root) async {
    final global = await _loadGlobal(root) ?? bundled;
    final overlay = await _findFile(root, '.dartitect/ecosystem-policy.json');
    if (overlay == null) return global;
    final decoded = jsonDecode(await overlay.readAsString());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Ecosystem overlay must be a JSON object.');
    }
    return EcosystemPolicy.withOverlay(global, decoded);
  }

  /// Synchronous equivalent for host callbacks.
  static EcosystemPolicy loadSync(Directory root) {
    final global = _loadGlobalSync(root) ?? bundled;
    final overlay = _findFileSync(root, '.dartitect/ecosystem-policy.json');
    if (overlay == null) return global;
    final decoded = jsonDecode(overlay.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Ecosystem overlay must be a JSON object.');
    }
    return EcosystemPolicy.withOverlay(global, decoded);
  }

  /// Policy bundled into installed CLI tooling.
  static final EcosystemPolicy bundled = EcosystemPolicy._bundled();

  // ignore: sort_constructors_first
  factory EcosystemPolicy._bundled() {
    const documentation = 'docs/guides/ecosystem-policy.md';
    final records = <String, EcosystemPolicyRecord>{};
    for (final entry in _bundledDecisions.entries) {
      final pieces = entry.value.split('|');
      final decision = _parseDecision(pieces[0]);
      final dimensions = _defaultDimensions(entry.key, decision);
      records[entry.key] = EcosystemPolicyRecord(
        package: entry.key,
        decision: decision,
        boundary: dimensions.boundary,
        maturity: dimensions.maturity,
        adoptionStatus: dimensions.adoptionStatus,
        replacement: pieces.length > 1 && pieces[1].isNotEmpty
            ? pieces[1]
            : null,
        owner: 'versioned Dartitect ecosystem ledger',
        documentation: documentation,
        conflictsWith: pieces.length > 2 && pieces[2].isNotEmpty
            ? pieces[2].split(',')
            : const <String>[],
        compatibility: pieces.length > 3 && pieces[3].isNotEmpty
            ? pieces[3]
            : null,
      );
    }
    return EcosystemPolicy._(
      profile: 'native_strict',
      documentation: documentation,
      records: Map<String, EcosystemPolicyRecord>.unmodifiable(records),
      exceptions: const <EcosystemPolicyException>[],
      workspaceReviewedPackages: const <String>{},
      validationFindings: const <EcosystemAuditFinding>[],
      overlays: const <String, List<_OverlayRecord>>{},
    );
  }

  /// Active profile name.
  final String profile;

  /// Policy guide path.
  final String documentation;

  /// Global decisions keyed by pub package.
  final Map<String, EcosystemPolicyRecord> records;

  /// Global and overlay scopes.
  final List<EcosystemPolicyException> exceptions;

  /// Exact resolved package cohort reviewed for Dartitect's own release audit.
  final Set<String> workspaceReviewedPackages;

  /// Invalid ledger or overlay entries emitted as DT1018.
  final List<EcosystemAuditFinding> validationFindings;

  final Map<String, List<_OverlayRecord>> _overlays;

  /// Returns the global record or a visible unreviewed record.
  EcosystemPolicyRecord explain(String package) =>
      records[package] ??
      EcosystemPolicyRecord(
        package: package,
        decision: EcosystemDecision.unreviewed,
        boundary: 'unreviewed',
        maturity: 'unreviewed',
        adoptionStatus: 'unreviewed',
        owner: 'unassigned',
        documentation: documentation,
      );

  EcosystemPolicyRecord _explainForOwners(
    String package,
    Set<String> directOwners,
    DateTime now,
  ) {
    final base = explain(package);
    if (base.decision == EcosystemDecision.prohibitedNativeStrict) return base;
    for (final overlay in _overlays[package] ?? const <_OverlayRecord>[]) {
      if (overlay.scope.isExpiredAt(now)) continue;
      if (directOwners.every(overlay.scope._acceptsOwner))
        return overlay.record;
    }
    return base;
  }

  /// Valid scope for [package] at [now], if one exists.
  EcosystemPolicyException? exceptionFor(
    String package,
    DateTime now, {
    String? directOwner,
  }) {
    for (final exception in exceptions) {
      if (exception.package == package &&
          !exception.isExpiredAt(now) &&
          (directOwner == null || exception._acceptsOwner(directOwner))) {
        return exception;
      }
    }
    return null;
  }

  /// Whether every transitive owner is covered by a valid scoped decision.
  bool allowsEveryOwner(
    String package,
    Set<String> directOwners,
    DateTime now,
  ) =>
      directOwners.isNotEmpty &&
      directOwners.every(
        (owner) => exceptionFor(package, now, directOwner: owner) != null,
      );

  /// Whether a reviewed package is allowed at this concrete source [path].
  bool allowsExceptionAt(String package, String path, DateTime now) {
    final normalized = path.replaceAll('\\', '/');
    final lib = normalized.lastIndexOf('/lib/');
    final relative = lib < 0 ? normalized : normalized.substring(lib + 1);
    return exceptions.any(
      (exception) =>
          exception.package == package &&
          !exception.isExpiredAt(now) &&
          exception.paths.any((glob) => _globMatches(glob, relative)),
    );
  }
}

/// One stable audit diagnostic.
final class EcosystemAuditFinding {
  /// Creates a dependency finding with every direct owner and route.
  const EcosystemAuditFinding({
    required this.code,
    required this.package,
    required this.message,
    required this.directOwners,
    this.dependencyPaths = const <String>[],
    this.replacement,
  });

  /// DT1017 for prohibitions/conflicts or DT1018 for review failures.
  final String code;

  /// Direct or transitive dependency.
  final String package;

  /// Sanitized remediation message.
  final String message;

  /// Every direct dependency that reaches [package].
  final List<String> directOwners;

  /// One deterministic resolved route per direct owner.
  final List<String> dependencyPaths;

  /// First sorted direct owner retained for source compatibility.
  String? get directOwner => directOwners.firstOrNull;

  /// Dartitect alternative or architectural replacement.
  final String? replacement;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'package': package,
    'message': message,
    'directOwners': directOwners,
    'dependencyPaths': dependencyPaths,
    if (replacement != null) 'replacement': replacement,
  };
}

/// Complete offline dependency classification.
final class EcosystemAuditReport {
  /// Creates a sorted report.
  const EcosystemAuditReport({required this.packages, required this.findings});

  /// Decision, owners, and routes for every resolved package.
  final List<Map<String, Object?>> packages;

  /// Policy violations.
  final List<EcosystemAuditFinding> findings;

  /// Whether no policy violation was found.
  bool get isClean => findings.isEmpty;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 2,
    'command': 'dependencies audit',
    'clean': isClean,
    'packages': packages,
    'diagnostics': <Object?>[for (final finding in findings) finding.toJson()],
  };
}

/// Offline direct/transitive dependency auditor.
final class EcosystemDependencyAuditor {
  /// Creates an auditor for a Dart/Flutter package root.
  EcosystemDependencyAuditor(
    this.root,
    this.policy, {
    this.blockUnreviewed = false,
  });

  /// Project root.
  final Directory root;

  /// Shared decision engine.
  final EcosystemPolicy policy;

  /// Whether an unreviewed package is release-blocking for this workspace.
  final bool blockUnreviewed;

  /// Audits package graph when available, with lockfile fallback.
  Future<EcosystemAuditReport> audit() async {
    final direct = await _directDependencies(root);
    final graph = await _resolvedGraph(root, direct);
    final findings = <EcosystemAuditFinding>[...policy.validationFindings];
    final packages = <Map<String, Object?>>[];
    final now = DateTime.now().toUtc();
    for (final package in graph.owners.keys.toList()..sort()) {
      final owners = graph.owners[package] ?? const <String>{};
      final paths = (graph.paths[package] ?? const <String>{}).toList()..sort();
      final record = policy._explainForOwners(package, owners, now);
      packages.add(<String, Object?>{
        ...record.toJson(),
        'direct': direct.contains(package),
        'directOwners': owners.toList()..sort(),
        'dependencyPaths': paths,
      });
      void addFinding(String code, String message) {
        findings.add(
          EcosystemAuditFinding(
            code: code,
            package: package,
            directOwners: owners.toList()..sort(),
            dependencyPaths: paths,
            replacement: record.replacement,
            message: message,
          ),
        );
      }

      switch (record.decision) {
        case EcosystemDecision.prohibitedNativeStrict:
          addFinding(
            'DT1017',
            'Package is universally prohibited by the Native Strict profile.',
          );
        case EcosystemDecision.advisoryAlternative:
          final activeConflicts = record.conflictsWith
              .where(graph.owners.containsKey)
              .toList();
          if (activeConflicts.isNotEmpty) {
            addFinding(
              'DT1017',
              'Equivalent instrumentation is active through '
                  '${activeConflicts.join(', ')}.',
            );
          }
        case EcosystemDecision.reviewedException:
          if (!policy.allowsEveryOwner(package, owners, now)) {
            addFinding(
              'DT1018',
              'A consumer-owned, scoped, non-expired overlay is required for '
                  'every direct owner.',
            );
          }
        case EcosystemDecision.unreviewed:
          if (blockUnreviewed &&
              !policy.workspaceReviewedPackages.contains(package)) {
            addFinding(
              'DT1018',
              'Unreviewed package blocks the Dartitect workspace release audit.',
            );
          }
        case EcosystemDecision.approved:
        case EcosystemDecision.approvedPrimitive:
          break;
      }
    }
    findings.sort((left, right) {
      final package = left.package.compareTo(right.package);
      return package != 0 ? package : left.code.compareTo(right.code);
    });
    return EcosystemAuditReport(
      packages: List<Map<String, Object?>>.unmodifiable(packages),
      findings: List<EcosystemAuditFinding>.unmodifiable(findings),
    );
  }
}

EcosystemPolicyRecord _parseRecord(
  String package,
  Map<String, Object?> value, {
  required String documentation,
  bool overlay = false,
}) {
  final rawDecision = value['decision'];
  final owner = value['owner'];
  if (!_packageName.hasMatch(package) ||
      rawDecision is! String ||
      owner is! String ||
      owner.trim().isEmpty) {
    throw const FormatException('Incomplete ecosystem policy decision.');
  }
  final decision = _parseDecision(rawDecision);
  final defaultDimensions = overlay
      ? const (
          boundary: 'consumer_scoped_boundary',
          maturity: 'consumer_reviewed',
          adoptionStatus: 'consumer_selected',
        )
      : _defaultDimensions(package, decision);
  final boundary = value['boundary'] ?? defaultDimensions.boundary;
  final maturity = value['maturity'] ?? defaultDimensions.maturity;
  final adoptionStatus =
      value['adoptionStatus'] ?? defaultDimensions.adoptionStatus;
  if (boundary is! String ||
      !_policyDimension.hasMatch(boundary) ||
      maturity is! String ||
      !_policyDimension.hasMatch(maturity) ||
      adoptionStatus is! String ||
      !_policyDimension.hasMatch(adoptionStatus)) {
    throw const FormatException('Incomplete ecosystem policy decision.');
  }
  if (overlay &&
      !const <EcosystemDecision>{
        EcosystemDecision.approved,
        EcosystemDecision.advisoryAlternative,
        EcosystemDecision.reviewedException,
      }.contains(decision)) {
    throw const FormatException('Consumer overlay cannot add prohibitions.');
  }
  final conflictsWith = _packageList(value['conflictsWith']);
  return EcosystemPolicyRecord(
    package: package,
    decision: decision,
    boundary: boundary,
    maturity: maturity,
    adoptionStatus: adoptionStatus,
    owner: owner,
    documentation: documentation,
    replacement: value['replacement'] as String?,
    publisher: value['publisher'] as String?,
    repository: value['repository'] as String?,
    compatibility: value['compatibility'] as String?,
    conflictsWith: conflictsWith,
  );
}

EcosystemPolicyException? _parseException(Object? value) {
  if (value is! Map<String, Object?>) return null;
  final package = value['package'];
  final owner = value['owner'];
  final reason = value['reason'];
  final expires = value['expiresOn'];
  final rawPaths = value['paths'];
  final rawDirectOwners = value['directOwners'];
  if (package is! String ||
      !_packageName.hasMatch(package) ||
      owner is! String ||
      owner.trim().isEmpty ||
      reason is! String ||
      reason.trim().isEmpty ||
      expires is! String ||
      rawPaths is! List<Object?> ||
      rawPaths.isEmpty ||
      rawDirectOwners != null &&
          (rawDirectOwners is! List<Object?> || rawDirectOwners.isEmpty)) {
    return null;
  }
  DateTime expiresOn;
  try {
    expiresOn = DateTime.parse('${expires}T00:00:00Z');
  } on FormatException {
    return null;
  }
  final paths = <String>[];
  for (final raw in rawPaths) {
    if (raw is! String ||
        raw.trim().isEmpty ||
        raw == '*' ||
        raw == '**' ||
        raw == '**/*' ||
        raw.startsWith('/') ||
        raw.contains('\\') ||
        raw.split('/').contains('..')) {
      return null;
    }
    paths.add(raw);
  }
  final directOwners = <String>[];
  if (rawDirectOwners is List<Object?>) {
    for (final raw in rawDirectOwners) {
      if (raw is! String ||
          !_packageName.hasMatch(raw) ||
          directOwners.contains(raw)) {
        return null;
      }
      directOwners.add(raw);
    }
  }
  return EcosystemPolicyException(
    package: package,
    owner: owner,
    reason: reason,
    expiresOn: expiresOn,
    paths: List<String>.unmodifiable(paths),
    directOwners: List<String>.unmodifiable(directOwners),
  );
}

EcosystemAuditFinding _invalidOverlayFinding([String package = '<policy>']) =>
    EcosystemAuditFinding(
      code: 'DT1018',
      package: package,
      message: 'The ecosystem policy contains an invalid consumer overlay.',
      directOwners: const <String>[],
    );

Future<Set<String>> _directDependencies(Directory root) async {
  final pubspec = File(_join(root.path, 'pubspec.yaml'));
  if (!await pubspec.exists()) {
    throw FileSystemException('pubspec.yaml was not found', pubspec.path);
  }
  final dependencies = <String>{};
  var section = false;
  for (final line in await pubspec.readAsLines()) {
    if (RegExp(r'^(dependencies|dev_dependencies):\s*$').hasMatch(line)) {
      section = true;
      continue;
    }
    if (line.isNotEmpty && !line.startsWith(' ')) section = false;
    if (!section) continue;
    final match = RegExp(r'^  ([a-zA-Z_][a-zA-Z0-9_]*):').firstMatch(line);
    if (match != null) dependencies.add(match.group(1)!);
  }
  return dependencies;
}

final class _ResolvedGraph {
  const _ResolvedGraph(this.owners, this.paths);

  final Map<String, Set<String>> owners;
  final Map<String, Set<String>> paths;
}

Future<_ResolvedGraph> _resolvedGraph(
  Directory root,
  Set<String> direct,
) async {
  final graph = File(_join(root.path, '.dart_tool/package_graph.json'));
  if (await graph.exists()) {
    final decoded = jsonDecode(await graph.readAsString());
    if (decoded is Map<String, Object?> &&
        decoded['packages'] is List<Object?>) {
      final edges = <String, Set<String>>{};
      for (final raw in decoded['packages']! as List<Object?>) {
        if (raw is! Map<String, Object?> || raw['name'] is! String) continue;
        edges[raw['name']! as String] = <String>{
          ..._strings(raw['dependencies']),
          ..._strings(raw['devDependencies']),
        };
      }
      final owners = <String, Set<String>>{};
      final paths = <String, Set<String>>{};
      for (final owner in direct.toList()..sort()) {
        final pending = <List<String>>[
          <String>[owner],
        ];
        final visited = <String>{};
        while (pending.isNotEmpty) {
          final route = pending.removeAt(0);
          final package = route.last;
          if (!visited.add(package)) continue;
          owners.putIfAbsent(package, () => <String>{}).add(owner);
          paths.putIfAbsent(package, () => <String>{}).add(route.join(' > '));
          for (final dependency
              in (edges[package] ?? const <String>{}).toList()..sort()) {
            pending.add(<String>[...route, dependency]);
          }
        }
      }
      return _ResolvedGraph(owners, paths);
    }
  }
  final owners = <String, Set<String>>{
    for (final package in direct) package: <String>{package},
  };
  final paths = <String, Set<String>>{
    for (final package in direct) package: <String>{package},
  };
  final lock = File(_join(root.path, 'pubspec.lock'));
  if (await lock.exists()) {
    var packages = false;
    for (final line in await lock.readAsLines()) {
      if (line == 'packages:') {
        packages = true;
        continue;
      }
      if (packages && line.isNotEmpty && !line.startsWith(' ')) break;
      final match = RegExp(r'^  ([a-zA-Z_][a-zA-Z0-9_]*):\s*$')
          .firstMatch(line);
      if (packages && match != null) {
        owners.putIfAbsent(match.group(1)!, () => <String>{});
        paths.putIfAbsent(match.group(1)!, () => <String>{});
      }
    }
  }
  return _ResolvedGraph(owners, paths);
}

Iterable<String> _strings(Object? value) =>
    value is List<Object?> ? value.whereType<String>() : const <String>[];

List<String> _packageList(Object? raw) {
  if (raw == null) return const <String>[];
  if (raw is! List<Object?>) {
    throw const FormatException('Invalid package list.');
  }
  final output = <String>[];
  for (final value in raw) {
    if (value is! String ||
        !_packageName.hasMatch(value) ||
        output.contains(value)) {
      throw const FormatException('Invalid package list.');
    }
    output.add(value);
  }
  return List<String>.unmodifiable(output);
}

EcosystemDecision _parseDecision(String value) => switch (value) {
  'approved' => EcosystemDecision.approved,
  'approved_primitive' => EcosystemDecision.approvedPrimitive,
  'advisory_alternative' => EcosystemDecision.advisoryAlternative,
  'reviewed_exception' => EcosystemDecision.reviewedException,
  'prohibited_native_strict' => EcosystemDecision.prohibitedNativeStrict,
  _ => throw const FormatException('Unknown ecosystem policy decision.'),
};

String _decisionName(EcosystemDecision value) => switch (value) {
  EcosystemDecision.approved => 'approved',
  EcosystemDecision.approvedPrimitive => 'approved_primitive',
  EcosystemDecision.advisoryAlternative => 'advisory_alternative',
  EcosystemDecision.reviewedException => 'reviewed_exception',
  EcosystemDecision.prohibitedNativeStrict => 'prohibited_native_strict',
  EcosystemDecision.unreviewed => 'unreviewed',
};

Future<EcosystemPolicy?> _loadGlobal(Directory root) async {
  final file = await _findFile(root, 'tool/ecosystem_policy.json');
  if (file == null) return null;
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Ecosystem policy must be a JSON object.');
  }
  return EcosystemPolicy.fromJson(decoded);
}

EcosystemPolicy? _loadGlobalSync(Directory root) {
  final file = _findFileSync(root, 'tool/ecosystem_policy.json');
  if (file == null) return null;
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Ecosystem policy must be a JSON object.');
  }
  return EcosystemPolicy.fromJson(decoded);
}

Future<File?> _findFile(Directory root, String relative) async {
  var directory = root.absolute;
  while (true) {
    final file = File(_join(directory.path, relative));
    if (await file.exists()) return file;
    final parent = directory.parent;
    if (parent.path == directory.path) return null;
    directory = parent;
  }
}

File? _findFileSync(Directory root, String relative) {
  var directory = root.absolute;
  while (true) {
    final file = File(_join(directory.path, relative));
    if (file.existsSync()) return file;
    final parent = directory.parent;
    if (parent.path == directory.path) return null;
    directory = parent;
  }
}

String _join(String left, String right) =>
    '$left${Platform.pathSeparator}${right.replaceAll('/', Platform.pathSeparator)}';

final _packageName = RegExp(r'^[a-z_][a-z0-9_]*$');
final _policyDimension = RegExp(r'^[a-z][a-z0-9_]*$');

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

const _bundledDecisions = <String, String>{
  'app_tracking_transparency': 'advisory_alternative|dartitect_privacy|',
  'bloc': 'prohibited_native_strict|constructor injection and Dartitect Commands/resources|',
  'brasil_fields':
      'advisory_alternative|dartitect_locale_br for CEP-only values|',
  'build_runner': 'approved||',
  'collection': 'approved||',
  'crypto': 'approved||',
  'dart_polylabel2': 'advisory_alternative|dartitect_geometry|',
  'dart_style': 'approved||',
  'dio': 'approved||',
  'elementary':
      'prohibited_native_strict|constructor injection and explicit ViewModels|',
  'flutter': 'approved||',
  'flutter_bloc': 'prohibited_native_strict|constructor injection and Dartitect Commands/resources|',
  'flutter_image_compress': 'reviewed_exception||',
  'flutter_localizations': 'approved||',
  'flutter_mobx':
      'prohibited_native_strict|constructor injection and Dartitect resources|',
  'flutter_modular': 'prohibited_native_strict|constructor injection and explicit composition roots|',
  'flutter_native_splash': 'advisory_alternative|consumer-owned native assets plus dartitect_flutter FirstFrameGate|',
  'flutter_pdfview': 'reviewed_exception||',
  'flutter_riverpod': 'prohibited_native_strict|constructor injection and Dartitect Commands/resources|',
  'flutter_secure_storage': 'reviewed_exception||',
  'freezed': 'advisory_alternative|dartitect model sync for bounded value boilerplate|',
  'freezed_annotation':
      'advisory_alternative|DartitectValue for bounded value boilerplate|',
  'gal': 'advisory_alternative|dartitect_media|',
  'get': 'prohibited_native_strict|constructor injection and explicit composition roots|',
  'get_it': 'prohibited_native_strict|constructor injection and explicit composition roots|',
  'get_it_mixin': 'prohibited_native_strict|constructor injection and explicit composition roots|',
  'go_router': 'approved||',
  'hooks_riverpod': 'prohibited_native_strict|constructor injection and Dartitect Commands/resources|',
  'hydrated_bloc': 'prohibited_native_strict|consumer-owned persistence with Dartitect resources|',
  'image': 'reviewed_exception||',
  'image_picker': 'approved||',
  'injectable': 'prohibited_native_strict|constructor injection and explicit composition roots|',
  'intl': 'approved||',
  'json_annotation': 'approved||',
  'json_serializable': 'approved||',
  'lottie': 'reviewed_exception||',
  'listen': 'approved_primitive|||nominal interoperability with Flutter listenables is not established',
  'mapbox_maps_flutter': 'approved||',
  'mobx':
      'prohibited_native_strict|constructor injection and Dartitect resources|',
  'objectbox': 'approved||',
  'objectbox_flutter_libs': 'approved||',
  'objectbox_generator': 'approved||',
  'package_info_plus': 'approved||',
  'path': 'approved||',
  'path_provider': 'approved||',
  'pdf': 'reviewed_exception||',
  'printing': 'reviewed_exception||',
  'pro_image_editor': 'reviewed_exception||',
  'provider': 'prohibited_native_strict|constructor injection and explicit composition roots|',
  'retrofit':
      'advisory_alternative|explicit clients over dartitect_dio DioJsonClient|',
  'retrofit_generator': 'advisory_alternative|explicit endpoint clients|',
  'riverpod': 'prohibited_native_strict|constructor injection and Dartitect Commands/resources|',
  'riverpod_annotation': 'prohibited_native_strict|constructor injection and explicit composition roots|',
  'riverpod_generator': 'prohibited_native_strict|constructor injection and explicit composition roots|',
  'sentry': 'approved||',
  'sentry_dio': 'advisory_alternative|one reviewed Dio instrumentation path|dartitect_dio',
  'sentry_flutter': 'approved||',
  'share_plus': 'approved||',
  'shared_preferences': 'approved||',
  'signals':
      'prohibited_native_strict|Dartitect resources and native listenables|',
  'signals_flutter':
      'prohibited_native_strict|Dartitect resources and native listenables|',
  'stacked':
      'prohibited_native_strict|constructor injection and explicit ViewModels|',
  'url_launcher': 'approved||',
  'uuid': 'advisory_alternative|SecureUuidV4Generator when only UUID v4 is required|',
  'watch_it': 'prohibited_native_strict|constructor injection and explicit composition roots|',
  'workmanager': 'advisory_alternative|consumer-owned scheduling port around the native scheduler|',
};

({String boundary, String maturity, String adoptionStatus}) _defaultDimensions(
  String package,
  EcosystemDecision decision,
) {
  if (package == 'listen') {
    return (
      boundary: 'pure_dart_primitive',
      maturity: 'reviewed',
      adoptionStatus: 'deferred_until_real_consumer',
    );
  }
  return switch (decision) {
    EcosystemDecision.approved => (
      boundary: 'approved_consumer_boundary',
      maturity: 'reviewed',
      adoptionStatus: 'available_at_boundary',
    ),
    EcosystemDecision.approvedPrimitive => (
      boundary: 'approved_primitive',
      maturity: 'reviewed',
      adoptionStatus: 'available_at_boundary',
    ),
    EcosystemDecision.advisoryAlternative => (
      boundary: 'consumer_choice_boundary',
      maturity: 'reviewed',
      adoptionStatus: 'optional_consumer_choice',
    ),
    EcosystemDecision.reviewedException => (
      boundary: 'consumer_scoped_boundary',
      maturity: 'review_required',
      adoptionStatus: 'consumer_review_required',
    ),
    EcosystemDecision.prohibitedNativeStrict => (
      boundary: 'application_architecture',
      maturity: 'not_applicable',
      adoptionStatus: 'not_supported_native_strict',
    ),
    EcosystemDecision.unreviewed => (
      boundary: 'unreviewed',
      maturity: 'unreviewed',
      adoptionStatus: 'unreviewed',
    ),
  };
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
