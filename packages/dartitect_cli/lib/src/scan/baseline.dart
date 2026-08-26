import 'dart:convert';
import 'dart:io';

import '../diagnostics/models.dart';

/// Stable baseline schema. Line numbers are intentionally excluded.
final class DartitectBaseline {
  /// Creates a baseline from fingerprints.
  DartitectBaseline(Iterable<String> fingerprints)
    : fingerprints = Set<String>.unmodifiable(fingerprints);

  /// Loads and validates schema v1.
  factory DartitectBaseline.parse(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?> || decoded['schemaVersion'] != 1) {
      throw const FormatException('Unsupported Dartitect baseline schema.');
    }
    final values = decoded['fingerprints'];
    if (values is! List<Object?> || values.any((value) => value is! String)) {
      throw const FormatException('Baseline fingerprints must be strings.');
    }
    return DartitectBaseline(values.cast<String>());
  }

  /// Creates a baseline from current violations.
  factory DartitectBaseline.fromFindings(Iterable<DartitectFinding> findings) =>
      DartitectBaseline(findings.map(fingerprintFinding));

  /// Fingerprints of accepted findings.
  final Set<String> fingerprints;

  /// Loads [file].
  static Future<DartitectBaseline> load(File file) async =>
      DartitectBaseline.parse(await file.readAsString());

  /// Stable JSON, sorted for auditability.
  String encode() {
    final sorted = fingerprints.toList()..sort();
    return '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{'schemaVersion': 1, 'fingerprints': sorted})}\n';
  }
}

/// Fingerprint over code + normalized path + evidence, never line number.
String fingerprintFinding(DartitectFinding finding) {
  final value =
      '${finding.code}\u0000${_normalizePath(finding.path)}\u0000'
      '${(finding.evidence ?? '').trim()}';
  // FNV-1a 32-bit avoids platform-dependent signed 64-bit behavior.
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(value)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String _normalizePath(String? path) =>
    (path ?? '').replaceAll('\\', '/').replaceAll(RegExp(r'^\./'), '');

/// Index-aware list removal used by baseline reconciliation.
extension RemoveWhereFrom<T> on List<T> {
  /// Removes matching elements only at or after [start].
  void removeWhereFrom(int start, bool Function(T value) predicate) {
    for (var index = length - 1; index >= start; index -= 1) {
      if (predicate(this[index])) removeAt(index);
    }
  }
}
