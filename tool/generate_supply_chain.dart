import 'dart:convert';
import 'dart:io';

/// Generates or checks the deterministic workspace SBOM and license inventory.
Future<void> main(List<String> arguments) async {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final release = jsonDecode(
    File('${root.path}/tool/package_release_contract.json').readAsStringSync(),
  );
  if (release is! Map<String, Object?> || release['cohortVersion'] is! String) {
    throw const FormatException('Invalid package release cohort.');
  }
  final cohort = release['cohortVersion']! as String;
  final result = await Process.run('dart', const <String>[
    'pub',
    'deps',
    '--json',
  ], workingDirectory: root.path);
  if (result.exitCode != 0) {
    stderr.write(result.stderr);
    exitCode = result.exitCode;
    return;
  }
  final graph = jsonDecode(result.stdout as String) as Map<String, Object?>;
  final rawPackages = (graph['packages']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final config = jsonDecode(
    await File('${root.path}/.dart_tool/package_config.json').readAsString(),
  ) as Map<String, Object?>;
  final configUri = File('${root.path}/.dart_tool/package_config.json')
      .absolute
      .uri;
  final roots = <String, Uri>{
    for (final raw
        in (config['packages']! as List<Object?>).cast<Map<String, Object?>>())
      raw['name']! as String: configUri.resolve(raw['rootUri']! as String),
  };
  final packages = <Map<String, Object?>>[];
  final licenseInventory = <Map<String, Object?>>[];
  for (final package in rawPackages) {
    final name = package['name']! as String;
    final version = package['version']! as String;
    final discoveredLicense = await _licenseFor(roots[name]);
    final license =
        discoveredLicense.$1 == 'NOASSERTION' && package['source'] == 'sdk'
        ? ('BSD-3-Clause', 'SDK license')
        : discoveredLicense;
    final id = 'SPDXRef-Package-${_safeId(name)}';
    packages.add(<String, Object?>{
      'name': name,
      'SPDXID': id,
      'versionInfo': version,
      'downloadLocation': package['source'] == 'hosted'
          ? 'https://pub.dev/packages/$name/versions/$version'
          : 'NOASSERTION',
      'filesAnalyzed': false,
      'licenseConcluded': license.$1,
      'licenseDeclared': license.$1,
      'copyrightText': 'NOASSERTION',
    });
    licenseInventory.add(<String, Object?>{
      'name': name,
      'version': version,
      'source': package['source'],
      'license': license.$1,
      if (license.$2 != null) 'licenseFile': license.$2,
    });
  }
  packages.sort(
    (left, right) => '${left['name']}'.compareTo('${right['name']}'),
  );
  licenseInventory.sort(
    (left, right) => '${left['name']}'.compareTo('${right['name']}'),
  );
  final packageNames = rawPackages.map((package) => package['name']).toSet();
  final relationships = <Map<String, String>>[];
  for (final package in rawPackages) {
    final from = package['name']! as String;
    for (final dependency
        in (package['dependencies']! as List<Object?>).whereType<String>()) {
      if (!packageNames.contains(dependency)) continue;
      relationships.add(<String, String>{
        'spdxElementId': 'SPDXRef-Package-${_safeId(from)}',
        'relationshipType': 'DEPENDS_ON',
        'relatedSpdxElement': 'SPDXRef-Package-${_safeId(dependency)}',
      });
    }
  }
  relationships.sort(
    (left, right) => jsonEncode(left).compareTo(jsonEncode(right)),
  );
  final output = Directory('${root.path}/docs/release');
  await output.create(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  final sbom =
      '${encoder.convert(<String, Object?>{
        'spdxVersion': 'SPDX-2.3',
        'dataLicense': 'CC0-1.0',
        'SPDXID': 'SPDXRef-DOCUMENT',
        'name': 'Dartitect-workspace',
        'documentNamespace': 'https://github.com/ftr-tuta/dartitect/sbom/workspace-$cohort',
        'creationInfo': <String, Object?>{
          'created': '2026-08-25T00:00:00Z',
          'creators': <String>['Tool: dartitect-generate-supply-chain'],
        },
        'packages': packages,
        'relationships': relationships,
      })}\n';
  final licenses =
      '${encoder.convert(<String, Object?>{'schemaVersion': 1, 'generatedFor': 'release baseline $cohort', 'packages': licenseInventory})}\n';
  final sbomFile = File('${output.path}/sbom.spdx.json');
  final licenseFile = File('${output.path}/dependency-licenses.json');
  if (arguments.contains('--check')) {
    final mismatches = <String>[
      if (await _artifactMismatch(sbomFile, sbom) case final mismatch?)
        mismatch,
      if (await _artifactMismatch(licenseFile, licenses) case final mismatch?)
        mismatch,
    ];
    if (mismatches.isNotEmpty) {
      stderr.writeln(
        'Supply-chain artifacts are stale; run '
        'dart run tool/generate_supply_chain.dart.',
      );
      for (final mismatch in mismatches) {
        stderr.writeln(mismatch);
      }
      exitCode = 1;
      return;
    }
  } else {
    await sbomFile.writeAsString(sbom, flush: true);
    await licenseFile.writeAsString(licenses, flush: true);
  }
  final unknown = licenseInventory
      .where((entry) => entry['license'] == 'NOASSERTION')
      .length;
  stdout.writeln(
    '${arguments.contains('--check') ? 'Checked' : 'Generated'} SPDX SBOM '
    'for ${packages.length} packages; '
    '$unknown license declarations require review.',
  );
}

Future<(String, String?)> _licenseFor(Uri? rootUri) async {
  if (rootUri == null || rootUri.scheme != 'file') {
    return ('NOASSERTION', null);
  }
  final directory = Directory.fromUri(rootUri);
  if (!await directory.exists()) return ('NOASSERTION', null);
  final entities = await directory.list(followLinks: false).toList();
  final candidates = entities
      .whereType<File>()
      .where((file) => _fileName(file).toUpperCase().startsWith('LICENSE'))
      .toList();
  candidates.sort(
    (left, right) => left.uri.toString().compareTo(right.uri.toString()),
  );
  if (candidates.isEmpty) return ('NOASSERTION', null);
  final text = await candidates.first.readAsString();
  final licenseFileName = _canonicalLicenseFileName(candidates.first);
  final license = text.contains('Apache License')
      ? 'Apache-2.0'
      : text.contains('MIT License') ||
            text.contains('Permission is hereby granted, free of charge')
      ? 'MIT'
      : text.contains('Redistribution and use in source and binary forms')
      ? 'BSD-3-Clause'
      : 'NOASSERTION';
  return (license, licenseFileName);
}

String _safeId(String value) =>
    value.replaceAll(RegExp(r'[^A-Za-z0-9.-]'), '-');

String _fileName(File file) => file.uri.pathSegments.last;

String _canonicalLicenseFileName(File file) {
  final name = _fileName(file);
  return 'LICENSE${name.substring('LICENSE'.length)}';
}

Future<String?> _artifactMismatch(File file, String expected) async {
  if (!await file.exists()) return '${file.path}: missing';
  final actual = await file.readAsString();
  if (actual == expected) return null;
  try {
    final difference = _firstJsonDifference(
      jsonDecode(actual),
      jsonDecode(expected),
      r'$',
    );
    return difference == null
        ? '${file.path}: JSON matches but serialization differs'
        : '${file.path}: $difference';
  } on FormatException catch (error) {
    return '${file.path}: invalid tracked JSON: $error';
  }
}

String? _firstJsonDifference(Object? actual, Object? expected, String path) {
  if (actual is Map && expected is Map) {
    final keys = <Object?>{...actual.keys, ...expected.keys}.toList()
      ..sort((left, right) => '$left'.compareTo('$right'));
    for (final key in keys) {
      if (!actual.containsKey(key)) return '$path.$key is missing in tracked';
      if (!expected.containsKey(key)) {
        return '$path.$key exists only in tracked';
      }
      final difference = _firstJsonDifference(
        actual[key],
        expected[key],
        '$path.$key',
      );
      if (difference != null) return difference;
    }
    return null;
  }
  if (actual is List && expected is List) {
    if (actual.length != expected.length) {
      return '$path length is ${actual.length}; expected ${expected.length}';
    }
    for (var index = 0; index < actual.length; index += 1) {
      final difference = _firstJsonDifference(
        actual[index],
        expected[index],
        '$path[$index]',
      );
      if (difference != null) return difference;
    }
    return null;
  }
  if (actual == expected) return null;
  return '$path is ${jsonEncode(actual)}; expected ${jsonEncode(expected)}';
}
