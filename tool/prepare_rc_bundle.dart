import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Builds deterministic, unsigned RC package artifacts from one exact commit.
///
/// This is a staging operation, not V1S-16 materialization: it creates no tag,
/// signature, upload, release, or authorization receipt.
Future<void> main(List<String> arguments) async {
  Directory? staging;
  try {
    final options = _Options.parse(arguments);
    final root =
        options.root ?? File.fromUri(Platform.script).parent.parent.absolute;
    final sourceSha = await _resolveCommit(root, options.sourceRevision);
    final sourceTree = (await _gitText(root, <String>[
      'show',
      '-s',
      '--format=%T',
      sourceSha,
    ])).trim();
    final sourceMtime = (await _gitText(root, <String>[
      'show',
      '-s',
      '--format=%cI',
      sourceSha,
    ])).trim();
    final dirty = await _gitText(root, const <String>[
      'status',
      '--porcelain=v1',
      '--untracked-files=no',
    ]);
    if (dirty.trim().isNotEmpty) {
      throw StateError('RC bundle preparation requires a clean tracked tree.');
    }

    final release = _object(
      jsonDecode(
        await _gitText(root, <String>[
          'show',
          '$sourceSha:tool/package_release_contract.json',
        ]),
      ),
    );
    final contract = _object(
      jsonDecode(
        File('${root.path}/tool/rc_bundle_contract.json').readAsStringSync(),
      ),
    );
    _validateContracts(release, contract);
    final cohort = release['cohortVersion']! as String;
    final order = _strings(release['publicationOrder']);
    final layers = _layers(release['publicationLayers']);
    final positions = <String, int>{
      for (var index = 0; index < order.length; index += 1) order[index]: index,
    };
    final layerByPackage = <String, int>{
      for (var index = 0; index < layers.length; index += 1)
        for (final package in layers[index]) package: index,
    };

    final target =
        options.output ??
        Directory(
          '${root.path}/${contract['outputDirectory']}/$cohort/$sourceSha',
        );
    if (target.existsSync()) {
      throw StateError(
        'Refusing to overwrite existing RC bundle staging: ${target.path}',
      );
    }
    await target.parent.create(recursive: true);
    staging = await target.parent.createTemp('.dartitect-rc-staging-');
    final packagesDirectory = Directory('${staging.path}/packages');
    await packagesDirectory.create(recursive: true);
    final packageReceipts = <Map<String, Object?>>[];
    for (final package in order) {
      final index = positions[package]!;
      final pubspecSource = await _gitText(root, <String>[
        'show',
        '$sourceSha:packages/$package/pubspec.yaml',
      ]);
      if (_field(pubspecSource, 'name') != package ||
          _field(pubspecSource, 'version') != cohort) {
        throw StateError('$package is not part of the exact $cohort cohort.');
      }
      final prefix = (index + 1).toString().padLeft(2, '0');
      final archiveName = '$prefix-$package-$cohort.tar.gz';
      final archive = File('${packagesDirectory.path}/$archiveName');
      final verificationArchive = File(
        '${staging.path}/$package.verify.tar.gz',
      );
      await _git(root, <String>[
        'archive',
        '--format=tar.gz',
        '--mtime=$sourceMtime',
        '--output=${archive.path}',
        '$sourceSha:packages/$package',
      ]);
      await _git(root, <String>[
        'archive',
        '--format=tar.gz',
        '--mtime=$sourceMtime',
        '--output=${verificationArchive.path}',
        '$sourceSha:packages/$package',
      ]);
      final first = await archive.readAsBytes();
      final second = await verificationArchive.readAsBytes();
      if (sha256.convert(first) != sha256.convert(second)) {
        throw StateError('$package Git archive output is not reproducible.');
      }
      await verificationArchive.delete();
      packageReceipts.add(<String, Object?>{
        'package': package,
        'version': cohort,
        'layer': layerByPackage[package],
        'orderIndex': index,
        'archive': 'packages/$archiveName',
        'archiveBytes': await archive.length(),
        'archiveSha256': sha256.convert(first).toString(),
        'canonicalSourceSha256': await _canonicalSourceDigest(
          root,
          sourceSha,
          package,
        ),
        'hostedPubspec': _hostedPubspec(pubspecSource),
      });
    }

    final supplyChain = <String, Object?>{};
    for (final entry in const <MapEntry<String, String>>[
      MapEntry<String, String>('sbom', 'docs/release/sbom.spdx.json'),
      MapEntry<String, String>(
        'licenses',
        'docs/release/dependency-licenses.json',
      ),
      MapEntry<String, String>(
        'advisories',
        'docs/release/advisory-audit.adoc',
      ),
    ]) {
      final bytes = await _gitBytes(root, <String>[
        'show',
        '$sourceSha:${entry.value}',
      ]);
      supplyChain[entry.key] = <String, Object?>{
        'path': entry.value,
        'sha256': sha256.convert(bytes).toString(),
      };
    }
    final manifest = <String, Object?>{
      'schemaVersion': 1,
      'goal': 'V1S-16',
      'state': 'CANDIDATE_BUNDLE',
      'channel': 'signed-bundle',
      'cohortVersion': cohort,
      'sourceSha': sourceSha,
      'sourceTree': sourceTree,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'trackedTreeClean': true,
      'archiveFormat': 'tar.gz',
      'digestAlgorithm': 'sha256',
      'packageCount': order.length,
      'packages': packageReceipts,
      'supplyChain': supplyChain,
      'materialization': <String, Object?>{
        'authorized': false,
        'signed': false,
        'tagCreated': false,
        'uploaded': false,
      },
    };
    await File('${staging.path}/bundle-manifest.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
      flush: true,
    );
    await staging.rename(target.path);
    staging = null;
    stdout
      ..writeln('Prepared unsigned candidate bundle for $sourceSha.')
      ..writeln('Bundle: ${target.path}')
      ..writeln(
        'No signature, tag, upload, release, or authorization was created.',
      );
  } on Object catch (error) {
    stderr.writeln('RC bundle preparation failed: $error');
    exitCode = 1;
  } finally {
    if (staging case final directory? when directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }
}

void _validateContracts(
  Map<String, Object?> release,
  Map<String, Object?> contract,
) {
  if (release['schemaVersion'] != 1 ||
      contract['schemaVersion'] != 1 ||
      contract['goal'] != 'V1S-16' ||
      contract['supportedChannel'] != 'signed-bundle' ||
      contract['toolingState'] != 'PRE_MATERIALIZATION_READY' ||
      contract['materializationRequiresFormalReadiness'] != true) {
    throw const FormatException('Unsupported RC bundle contract.');
  }
  final order = _strings(release['publicationOrder']);
  final layers = _layers(release['publicationLayers']);
  if (order.length != 16 ||
      order.toSet().length != order.length ||
      {for (final layer in layers) ...layer}.length != order.length) {
    throw const FormatException('The RC publication cohort is incomplete.');
  }
}

Future<String> _canonicalSourceDigest(
  Directory root,
  String sourceSha,
  String package,
) async {
  final listing = await _gitText(root, <String>[
    'ls-tree',
    '-r',
    '--name-only',
    '$sourceSha:packages/$package',
  ]);
  final paths =
      const LineSplitter()
          .convert(listing)
          .where((path) => path.isNotEmpty)
          .toList()
        ..sort();
  final bytes = BytesBuilder(copy: false);
  for (final path in paths) {
    bytes
      ..add(utf8.encode(path))
      ..addByte(0)
      ..add(
        await _gitBytes(root, <String>[
          'show',
          '$sourceSha:packages/$package/$path',
        ]),
      )
      ..addByte(0);
  }
  return sha256.convert(bytes.takeBytes()).toString();
}

Future<String> _resolveCommit(Directory root, String revision) async {
  final value = (await _gitText(root, <String>[
    'rev-parse',
    '--verify',
    '$revision^{commit}',
  ])).trim();
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(value)) {
    throw StateError('Git returned an invalid source SHA.');
  }
  return value;
}

Future<void> _git(Directory root, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: root.path,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
}

Future<String> _gitText(Directory root, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: root.path,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
  return result.stdout as String;
}

Future<List<int>> _gitBytes(Directory root, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: root.path,
    stdoutEncoding: null,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
  return result.stdout as List<int>;
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

List<String> _strings(Object? value) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw const FormatException('Expected a string list.');
  }
  return value.cast<String>();
}

List<List<String>> _layers(Object? value) {
  if (value is! List<Object?>) {
    throw const FormatException('Expected publication layers.');
  }
  return <List<String>>[for (final layer in value) _strings(layer)];
}

String? _field(String source, String name) => RegExp(
  "^${RegExp.escape(name)}:\\s*['\"]?([^'\"\\s]+)['\"]?\\s*\$",
  multiLine: true,
).firstMatch(source)?.group(1);

Map<String, Object?> _hostedPubspec(String source) {
  final result = <String, Object?>{};
  final sections = <String, Map<String, Object?>>{
    'environment': <String, Object?>{},
    'dependencies': <String, Object?>{},
  };
  String? section;
  String? nestedKey;
  for (final raw in const LineSplitter().convert(source)) {
    final line = raw.split(' #').first;
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    final indent = line.length - line.trimLeft().length;
    final separator = line.indexOf(':');
    if (separator < 0) continue;
    final key = line.substring(indent, separator).trim();
    final rawValue = line.substring(separator + 1).trim();
    if (indent == 0) {
      nestedKey = null;
      section = sections.containsKey(key) ? key : null;
      if (key == 'name' || key == 'version') {
        result[key] = _yamlScalar(rawValue);
      }
      continue;
    }
    if (indent == 2 && section != null) {
      nestedKey = rawValue.isEmpty ? key : null;
      sections[section]![key] = rawValue.isEmpty
          ? <String, Object?>{}
          : _yamlScalar(rawValue);
      continue;
    }
    if (indent == 4 && section != null && nestedKey != null) {
      final nested = sections[section]![nestedKey] as Map<String, Object?>;
      nested[key] = _yamlScalar(rawValue);
    }
  }
  if (result['name'] is! String || result['version'] is! String) {
    throw const FormatException('Package pubspec is missing name or version.');
  }
  result.addAll(sections);
  return result;
}

String _yamlScalar(String value) {
  if (value.length >= 2 &&
      ((value.startsWith("'") && value.endsWith("'")) ||
          (value.startsWith('"') && value.endsWith('"')))) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

final class _Options {
  const _Options({required this.sourceRevision, this.root, this.output});

  factory _Options.parse(List<String> arguments) {
    var sourceRevision = 'HEAD';
    Directory? root;
    Directory? output;
    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      if (argument.startsWith('--source-sha=')) {
        sourceRevision = argument.substring('--source-sha='.length);
      } else if (argument == '--root' && index + 1 < arguments.length) {
        if (root != null) throw ArgumentError('Duplicate --root.');
        root = Directory(arguments[++index]).absolute;
      } else if (argument == '--output' && index + 1 < arguments.length) {
        if (output != null) throw ArgumentError('Duplicate --output.');
        output = Directory(arguments[++index]).absolute;
      } else {
        throw ArgumentError('Unknown or incomplete argument: $argument');
      }
    }
    return _Options(sourceRevision: sourceRevision, root: root, output: output);
  }

  final String sourceRevision;
  final Directory? root;
  final Directory? output;
}
