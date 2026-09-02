import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'dependency_snippets.dart';
import 'release_contract.dart';

/// Builds the deterministic, checksummed assets for the immutable Release.
Future<void> main(List<String> arguments) async {
  try {
    final options = _Options.parse(arguments);
    final root = options.root;
    final cohorts = ReleaseCohortContract.read(root);
    final contract = _object(
      jsonDecode(
        File('${root.path}/tool/package_release_contract.json')
            .readAsStringSync(),
      ),
    );
    if (cohorts.workspace.isPrerelease ||
        cohorts.workspace.channel != 'stable') {
      throw StateError(
        'Release assets reject the ${cohorts.workspace.channel} workspace '
        'cohort ${cohorts.workspace.version}.',
      );
    }
    if (options.output.existsSync()) {
      await options.output.delete(recursive: true);
    }
    await options.output.create(recursive: true);

    final readiness = File('${options.output.path}/actions-readiness-v1.json');
    await options.readiness.copy(readiness.path);
    final readinessObject = _object(jsonDecode(await readiness.readAsString()));
    if (readinessObject['sourceSha'] != options.sourceSha ||
        readinessObject['sourceTree'] != options.sourceTree ||
        readinessObject['runId'] != options.ciRunId ||
        readinessObject['runAttempt'] != options.ciRunAttempt) {
      throw StateError('Readiness identity differs from release inputs.');
    }

    await _writeJson(
      File('${options.output.path}/release-provenance.json'),
      <String, Object?>{
        'schemaVersion': 1,
        'release': cohorts.workspace.tag,
        'sourceSha': options.sourceSha,
        'sourceTree': options.sourceTree,
        'ciRunId': options.ciRunId,
        'ciRunAttempt': options.ciRunAttempt,
        'readinessSha256': await _digest(readiness),
        'distribution': 'github-only',
      },
    );

    final paths = _object(contract['packagePaths']);
    final order = _strings(contract['dependencyOrder']);
    final dependency = cohorts.workspaceDependency;
    await _writeJson(
      File('${options.output.path}/dartitect-git-manifest.json'),
      <String, Object?>{
        'schemaVersion': 1,
        'releaseVersion': cohorts.workspace.version,
        'releaseTag': cohorts.workspace.tag,
        'sourceSha': options.sourceSha,
        'repository': dependency['url'],
        'tagPattern': dependency['tagPattern'],
        'lockstep': true,
        'dependencyOrder': order,
        'packages': <Object?>[
          for (final package in order)
            <String, Object?>{
              'name': package,
              'path': paths[package],
              'version': cohorts.workspace.version,
            },
        ],
      },
    );

    final snippets = <String, List<int>>{
      for (final package in order)
        'packages/$package.yaml': utf8.encode(
          buildDependencySnippet(root, <String>[package]),
        ),
      for (final entry in dependencySnippetProfiles.entries)
        'profiles/${entry.key}.yaml': utf8.encode(
          buildDependencySnippet(root, entry.value),
        ),
    };
    await File('${options.output.path}/dependency-snippets.zip')
        .writeAsBytes(_zip(snippets), flush: true);

    for (final source in const <(String, String)>[
      ('docs/release/sbom.spdx.json', 'sbom.spdx.json'),
      ('docs/release/dependency-licenses.json', 'dependency-licenses.json'),
    ]) {
      await File('${root.path}/${source.$1}')
          .copy('${options.output.path}/${source.$2}');
    }

    final assets =
        options.output
            .listSync(followLinks: false)
            .whereType<File>()
            .where((file) => _basename(file.path) != 'SHA256SUMS')
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    final sums = StringBuffer();
    for (final asset in assets) {
      sums.writeln('${await _digest(asset)}  ${_basename(asset.path)}');
    }
    await File('${options.output.path}/SHA256SUMS')
        .writeAsString(sums.toString(), flush: true);
    stdout.writeln('Built ${assets.length + 1} Release assets.');
  } on Object catch (error) {
    stderr.writeln('Release asset build failed: $error');
    exitCode = error is FormatException ? 64 : 1;
  }
}

Future<void> _writeJson(File file, Map<String, Object?> value) =>
    file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(value)}\n',
      flush: true,
    );

Future<String> _digest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

List<int> _zip(Map<String, List<int>> entries) {
  final output = BytesBuilder(copy: false);
  final central = BytesBuilder(copy: false);
  var offset = 0;
  final sorted = entries.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  for (final entry in sorted) {
    final name = utf8.encode(entry.key);
    final data = entry.value;
    final crc = _crc32(data);
    final local = BytesBuilder(copy: false)
      ..add(_u32(0x04034b50))
      ..add(_u16(20))
      ..add(_u16(0x0800))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(33))
      ..add(_u32(crc))
      ..add(_u32(data.length))
      ..add(_u32(data.length))
      ..add(_u16(name.length))
      ..add(_u16(0))
      ..add(name)
      ..add(data);
    final localBytes = local.takeBytes();
    output.add(localBytes);
    central
      ..add(_u32(0x02014b50))
      ..add(_u16(20))
      ..add(_u16(20))
      ..add(_u16(0x0800))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(33))
      ..add(_u32(crc))
      ..add(_u32(data.length))
      ..add(_u32(data.length))
      ..add(_u16(name.length))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u32(0))
      ..add(_u32(offset))
      ..add(name);
    offset += localBytes.length;
  }
  final centralBytes = central.takeBytes();
  output
    ..add(centralBytes)
    ..add(_u32(0x06054b50))
    ..add(_u16(0))
    ..add(_u16(0))
    ..add(_u16(sorted.length))
    ..add(_u16(sorted.length))
    ..add(_u32(centralBytes.length))
    ..add(_u32(offset))
    ..add(_u16(0));
  return output.takeBytes();
}

int _crc32(List<int> data) {
  var crc = 0xffffffff;
  for (final byte in data) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit += 1) {
      crc = (crc & 1) == 1 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

Uint8List _u16(int value) =>
    (ByteData(2)..setUint16(0, value, Endian.little)).buffer.asUint8List();

Uint8List _u32(int value) =>
    (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List();

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

List<String> _strings(Object? value) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw const FormatException('Expected a JSON string list.');
  }
  return value.cast<String>();
}

String _basename(String path) =>
    path.split(Platform.pathSeparator).where((part) => part.isNotEmpty).last;

final class _Options {
  const _Options({
    required this.root,
    required this.output,
    required this.readiness,
    required this.sourceSha,
    required this.sourceTree,
    required this.ciRunId,
    required this.ciRunAttempt,
  });

  factory _Options.parse(List<String> arguments) {
    final values = <String, String>{};
    for (final argument in arguments) {
      final match = RegExp(r'^--([a-z-]+)=(.+)$').firstMatch(argument);
      if (match == null || values.containsKey(match.group(1))) {
        throw FormatException('Invalid or duplicate argument: $argument');
      }
      values[match.group(1)!] = match.group(2)!;
    }
    final sourceSha = values['source-sha'];
    final sourceTree = values['source-tree'];
    final ciRunId = int.tryParse(values['ci-run-id'] ?? '');
    final ciRunAttempt = int.tryParse(values['ci-run-attempt'] ?? '');
    if ((values.length != 6 && values.length != 7) ||
        values['output'] == null ||
        values['readiness'] == null ||
        sourceSha == null ||
        !RegExp(r'^[0-9a-f]{40}$').hasMatch(sourceSha) ||
        sourceTree == null ||
        !RegExp(r'^[0-9a-f]{40}$').hasMatch(sourceTree) ||
        ciRunId == null ||
        ciRunId <= 0 ||
        ciRunAttempt == null ||
        ciRunAttempt <= 0) {
      throw const FormatException(
        'Required valid --output, --readiness, --source-sha, --source-tree, '
        '--ci-run-id, and --ci-run-attempt; --root is optional.',
      );
    }
    final readiness = File(values['readiness']!).absolute;
    if (!readiness.existsSync()) {
      throw const FormatException('Readiness manifest does not exist.');
    }
    return _Options(
      root: values['root'] == null
          ? File.fromUri(Platform.script).parent.parent.absolute
          : Directory(values['root']!).absolute,
      output: Directory(values['output']!).absolute,
      readiness: readiness,
      sourceSha: sourceSha,
      sourceTree: sourceTree,
      ciRunId: ciRunId,
      ciRunAttempt: ciRunAttempt,
    );
  }

  final Directory root;
  final Directory output;
  final File readiness;
  final String sourceSha;
  final String sourceTree;
  final int ciRunId;
  final int ciRunAttempt;
}
