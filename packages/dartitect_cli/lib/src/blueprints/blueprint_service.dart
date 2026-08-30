import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../generation/generation_engine.dart';

/// Validated local blueprint and its static generation operations.
final class DartitectBlueprintReport {
  /// Creates a deterministic blueprint report.
  const DartitectBlueprintReport({
    required this.id,
    required this.version,
    required this.manifestPath,
    required this.manifestSha256,
    required this.operations,
  });

  /// Closed blueprint identifier.
  final String id;

  /// Consumer-controlled positive blueprint version.
  final int version;

  /// Project-relative local manifest path.
  final String manifestPath;

  /// Digest locking the closed manifest bytes.
  final String manifestSha256;

  /// Static template and digest-lock operations.
  final List<FileGenerationOperation> operations;

  /// Stable read-only result.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'command': 'blueprint check',
    'valid': true,
    'id': id,
    'version': version,
    'manifest': manifestPath,
    'manifestSha256': manifestSha256,
    'outputs': operations.map((operation) => operation.relativePath).toList(),
  };
}

/// Validates local, data-only architecture/test blueprints.
final class DartitectBlueprintService {
  /// Creates a service confined to [root].
  DartitectBlueprintService(Directory root) : root = root.absolute;

  /// Project boundary containing both blueprint and destination paths.
  final Directory root;

  /// Validates [path] and renders static operations without writing.
  Future<DartitectBlueprintReport> inspect(String path) async {
    final boundary = await root.resolveSymbolicLinks();
    final portable = _relative(path, description: 'blueprint path');
    final candidate = File(_join(root.path, portable));
    final manifest = await FileSystemEntity.isDirectory(candidate.path)
        ? File(_join(candidate.path, 'blueprint.json'))
        : candidate;
    if (!await manifest.exists()) {
      throw const FormatException('Blueprint manifest does not exist.');
    }
    final resolvedManifest = await manifest.resolveSymbolicLinks();
    _contained(boundary, resolvedManifest, 'blueprint manifest');
    final bytes = await File(resolvedManifest).readAsBytes();
    final decoded = jsonDecode(utf8.decode(bytes));
    const manifestKeys = <String>{
      'schemaVersion',
      'id',
      'version',
      'templates',
    };
    if (decoded is! Map<String, Object?> ||
        decoded.keys.toSet().difference(manifestKeys).isNotEmpty ||
        manifestKeys.difference(decoded.keys.toSet()).isNotEmpty ||
        decoded['schemaVersion'] != 1 ||
        decoded['id'] is! String ||
        decoded['version'] is! int ||
        decoded['templates'] is! List<Object?>) {
      throw const FormatException('Unsupported closed blueprint manifest.');
    }
    final id = decoded['id']! as String;
    final version = decoded['version']! as int;
    if (!RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(id) || version < 1) {
      throw const FormatException('Blueprint id or version is invalid.');
    }
    final operations = <FileGenerationOperation>[];
    final locks = <Map<String, Object?>>[];
    final destinations = <String>{};
    for (final raw in decoded['templates']! as List<Object?>) {
      const templateKeys = <String>{'source', 'path', 'sha256'};
      if (raw is! Map<String, Object?> ||
          raw.keys.toSet().difference(templateKeys).isNotEmpty ||
          templateKeys.difference(raw.keys.toSet()).isNotEmpty ||
          raw['source'] is! String ||
          raw['path'] is! String ||
          raw['sha256'] is! String) {
        throw const FormatException('Unsupported blueprint template entry.');
      }
      final source = _relative(
        raw['source']! as String,
        description: 'template source',
      );
      final destination = _relative(
        raw['path']! as String,
        description: 'template destination',
      );
      if (!destinations.add(destination)) {
        throw const FormatException('Blueprint template paths must be unique.');
      }
      if (!_architectureTemplatePath(destination)) {
        throw const FormatException(
          'Blueprint outputs are limited to architecture and test paths.',
        );
      }
      final sourceFile = File(
        _join(File(resolvedManifest).parent.path, source),
      );
      if (!await sourceFile.exists()) {
        throw const FormatException('Blueprint template source is missing.');
      }
      final resolvedSource = await sourceFile.resolveSymbolicLinks();
      _contained(
        File(resolvedManifest).parent.resolveSymbolicLinksSync(),
        resolvedSource,
        'template source',
      );
      final templateBytes = await File(resolvedSource).readAsBytes();
      final digest = sha256.convert(templateBytes).toString();
      if (raw['sha256'] != digest) {
        throw const FormatException(
          'Blueprint template digest does not match.',
        );
      }
      operations.add(
        FileGenerationOperation(
          relativePath: destination,
          content: utf8.decode(templateBytes),
          rendererId: 'blueprint.$id.template',
          sourcePath: _portable(resolvedSource.substring(boundary.length + 1)),
          inputSignature: digest,
        ),
      );
      locks.add(<String, Object?>{'path': destination, 'sha256': digest});
    }
    operations.sort(
      (left, right) => left.relativePath.compareTo(right.relativePath),
    );
    final manifestDigest = sha256.convert(bytes).toString();
    operations.add(
      FileGenerationOperation(
        relativePath: '.dartitect/blueprints/$id.lock.json',
        content:
            '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{'schemaVersion': 1, 'id': id, 'version': version, 'manifestSha256': manifestDigest, 'templates': locks})}\n',
        rendererId: 'blueprint.$id.digest-lock',
        sourcePath: _portable(resolvedManifest.substring(boundary.length + 1)),
        inputSignature: manifestDigest,
      ),
    );
    return DartitectBlueprintReport(
      id: id,
      version: version,
      manifestPath: _portable(resolvedManifest.substring(boundary.length + 1)),
      manifestSha256: manifestDigest,
      operations: List<FileGenerationOperation>.unmodifiable(operations),
    );
  }
}

bool _architectureTemplatePath(String path) =>
    path.startsWith('test/') ||
    path.startsWith('integration_test/') ||
    path.startsWith('docs/architecture/') ||
    path.startsWith('.dartitect/architecture/');

String _relative(String value, {required String description}) {
  final portable = _portable(value);
  if (portable.isEmpty ||
      portable.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(portable) ||
      portable
          .split('/')
          .any(
            (segment) => segment.isEmpty || segment == '.' || segment == '..',
          )) {
    throw FormatException('$description must be a confined relative path.');
  }
  return portable;
}

void _contained(String boundary, String candidate, String description) {
  final prefix = boundary.endsWith(Platform.pathSeparator)
      ? boundary
      : '$boundary${Platform.pathSeparator}';
  if (candidate != boundary && !candidate.startsWith(prefix)) {
    throw FormatException('$description escapes its allowed boundary.');
  }
}

String _portable(String value) => value.replaceAll('\\', '/');

String _join(String left, String right) =>
    '$left${Platform.pathSeparator}${right.replaceAll('/', Platform.pathSeparator)}';
