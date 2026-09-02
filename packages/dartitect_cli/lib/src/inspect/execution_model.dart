import 'dart:io';

import '../diagnostics/models.dart';

/// Read-only execution-model heuristic report.
final class ExecutionModelInspection {
  /// Creates one deterministic report.
  const ExecutionModelInspection({
    required this.dartFileCount,
    required this.findings,
  });

  /// Files considered by the inspector.
  final int dartFileCount;

  /// Informational or structurally strong runtime-efficiency findings.
  final List<DartitectFinding> findings;

  /// Stable schema-1 machine representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'command': 'inspect execution-model',
    'dartFileCount': dartFileCount,
    'findings': findings.map((finding) => finding.toJson()).toList(),
    'findingCount': findings.length,
    'exitCode': 0,
  };
}

/// Bounded, non-executing source inspector for runtime-efficiency patterns.
final class ExecutionModelInspector {
  /// Creates an inspector confined to [root].
  ExecutionModelInspector(Directory root) : root = root.absolute;

  /// Project root. Public findings contain relative paths only.
  final Directory root;

  /// Inspects source without invoking analyzers, builds, or application code.
  Future<ExecutionModelInspection> inspect() async {
    if (!await root.exists()) {
      throw FileSystemException('Project root does not exist', root.path);
    }
    final files = <File>[];
    await _discover(root, files);
    files.sort((left, right) => left.path.compareTo(right.path));
    final findings = <DartitectFinding>[];
    for (final file in files) {
      final source = await file.readAsString();
      final path = _relative(file.path);
      _inspectSource(path, source, findings);
    }
    findings.sort(_compareFinding);
    return ExecutionModelInspection(
      dartFileCount: files.length,
      findings: List<DartitectFinding>.unmodifiable(findings),
    );
  }

  void _inspectSource(
    String path,
    String source,
    List<DartitectFinding> findings,
  ) {
    void match(
      String code,
      RegExp expression,
      String message,
      String remediation, {
      FindingSeverity severity = FindingSeverity.info,
    }) {
      final result = expression.firstMatch(source);
      if (result == null) return;
      findings.add(
        DartitectFinding(
          code: code,
          severity: severity,
          message: message,
          path: path,
          line: _lineAt(source, result.start),
          evidence: _evidence[code],
          remediation: remediation,
          confidence: severity == FindingSeverity.warning ? 0.9 : 0.65,
        ),
      );
    }

    match(
      'DT2200',
      RegExp(r'\.(?:toList|toSet)\s*\('),
      'An eager collection materialization may increase latency and memory.',
      'Keep the source lazy or collect into an explicit bounded buffer.',
    );
    match(
      'DT2201',
      RegExp(r'\.removeAt\s*\(\s*0\s*\)'),
      'A List is used as a FIFO with linear front removal.',
      'Use ListQueue or a bounded ring buffer for queue semantics.',
      severity: FindingSeverity.warning,
    );
    match(
      'DT2202',
      RegExp(
        r'(?:final|late\s+final)\s+(?:List|Map|Set)<[^;]+>\s+_\w+\s*=\s*<',
      ),
      'A retained collection has no visible capacity policy.',
      'Declare a bound, eviction policy, or externally owned persistence seam.',
    );
    if (RegExp(r'List(?:<[^>]+>)?\.of\s*\([^)]*listeners').hasMatch(source) &&
        RegExp(r'listeners\s*\.contains\s*\(').hasMatch(source)) {
      final offset = source.indexOf('listeners');
      findings.add(
        DartitectFinding(
          code: 'DT2203',
          severity: FindingSeverity.warning,
          message: 'Listener dispatch combines a snapshot with linear membership checks.',
          path: path,
          line: _lineAt(source, offset < 0 ? 0 : offset),
          evidence: _evidence['DT2203'],
          remediation: 'Use a tombstoned listener registry with reentrancy-safe linear dispatch.',
          confidence: 0.95,
        ),
      );
    }
    match(
      'DT2204',
      RegExp(r'\.(?:sort|sorted)\s*\('),
      'A sort appears on a potentially repeated execution path.',
      'Maintain stable admission order or precompile the ordering once.',
    );
    match(
      'DT2205',
      RegExp(
        r'dependenc\w*[^;]{0,240}\.(?:any|every|where)\s*\(',
        dotAll: true,
      ),
      'Dependency readiness appears to rescan prerequisite collections.',
      'Build a dependent map and update indegrees as nodes complete.',
    );
    match(
      'DT2206',
      RegExp(r'Future\s*\.\s*wait[^;]{0,320}\.map\s*\(', dotAll: true),
      'Future.wait admits a mapped input without a visible concurrency bound.',
      'Use a bounded worker lane and pause the producer at admission capacity.',
      severity: FindingSeverity.warning,
    );
    match(
      'DT2207',
      RegExp(r'\.listen\s*\(\s*\([^)]*\)\s*async\b', dotAll: true),
      'An async stream listener has no visible pause or backpressure protocol.',
      'Pause input or await each item through an explicit incremental consumer.',
      severity: FindingSeverity.warning,
    );
    match(
      'DT2208',
      RegExp(
        r'StreamController(?:<[^;]+?>)?\s*\([^;]{0,240}sync\s*:\s*true',
        dotAll: true,
      ),
      'A synchronous StreamController requires a reentrancy justification.',
      'Test nested add, pause, cancellation, and dispose or use async delivery.',
    );
    match(
      'DT2209',
      RegExp(
        r'async\s*\*[^}]{0,600}(?:await\b|\bfor\s*\(|\bwhile\s*\()[^}]*yield\b',
        dotAll: true,
      ),
      'An async generator may perform substantial work before its first yield.',
      'Keep CPU and I/O bounded between emissions or move work behind a pool.',
    );
    final toSourceMatches = RegExp(r'\.toSource\s*\(')
        .allMatches(source)
        .toList();
    if (toSourceMatches.length > 1) {
      findings.add(
        DartitectFinding(
          code: 'DT2210',
          severity: FindingSeverity.info,
          message: 'The same source file serializes analyzer nodes repeatedly.',
          path: path,
          line: _lineAt(source, toSourceMatches[1].start),
          evidence: _evidence['DT2210'],
          remediation:
              'Reuse the original source string or one serialized projection.',
          confidence: 0.8,
        ),
      );
    }
    match(
      'DT2211',
      RegExp(
        r'(?:for|while)\s*\([^)]*\)\s*\{[^}]{0,600}\.contains\s*\(',
        dotAll: true,
      ),
      'A loop performs repeated linear membership checks.',
      'Precompute a Set or indexed registry before entering the hot loop.',
    );
  }

  Future<void> _discover(Directory directory, List<File> output) async {
    final relative = _relative(directory.path);
    if (relative != '.' &&
        await File(_join(directory.path, 'pubspec.yaml')).exists()) {
      return;
    }
    final segments = relative.replaceAll('\\', '/').split('/');
    if (segments.any(_ignoredDirectories.contains)) return;
    final entities = await directory.list(followLinks: false).toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    for (final entity in entities) {
      if (entity is Directory) {
        await _discover(entity, output);
      } else if (entity is File &&
          entity.path.endsWith('.dart') &&
          !_isGenerated(entity.path)) {
        output.add(entity);
      }
    }
  }

  String _relative(String path) {
    final rootPath = root.path.replaceAll('\\', '/');
    final normalized = File(path).absolute.path.replaceAll('\\', '/');
    final prefix = rootPath.endsWith('/') ? rootPath : '$rootPath/';
    return normalized == rootPath ? '.' : normalized.substring(prefix.length);
  }

  static int _lineAt(String source, int offset) =>
      '\n'.allMatches(source.substring(0, offset)).length + 1;

  static int _compareFinding(DartitectFinding left, DartitectFinding right) {
    final path = (left.path ?? '').compareTo(right.path ?? '');
    if (path != 0) return path;
    final line = (left.line ?? 0).compareTo(right.line ?? 0);
    if (line != 0) return line;
    return left.code.compareTo(right.code);
  }

  static bool _isGenerated(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.endsWith('.g.dart') ||
        normalized.endsWith('.freezed.dart') ||
        normalized.endsWith('.gr.dart');
  }

  static String _join(String left, String right) =>
      '$left${Platform.pathSeparator}${right.replaceAll('/', Platform.pathSeparator)}';

  static const Set<String> _ignoredDirectories = <String>{
    '.dart_tool',
    '.git',
    '.symlinks',
    'build',
    'ephemeral',
    'Pods',
  };

  static const Map<String, String> _evidence = <String, String>{
    'DT2200': 'eager iterable materialization',
    'DT2201': 'front removal from List',
    'DT2202': 'retained collection without visible bound',
    'DT2203': 'snapshot plus contains dispatch',
    'DT2204': 'repeated sorting candidate',
    'DT2205': 'dependency readiness rescan',
    'DT2206': 'unbounded mapped Future.wait',
    'DT2207': 'async listen callback',
    'DT2208': 'synchronous stream controller',
    'DT2209': 'work before first yield',
    'DT2210': 'repeated analyzer source serialization',
    'DT2211': 'linear membership inside loop',
  };
}
