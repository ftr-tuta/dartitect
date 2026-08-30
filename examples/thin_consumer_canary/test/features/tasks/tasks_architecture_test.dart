import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generated slice keeps providers out of presentation and domain', () {
    final feature = Directory(
      '${_packageRoot('thin_consumer_canary').path}/lib/features/tasks',
    );
    final files = feature
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      final source = file.readAsStringSync();
      final name = file.uri.pathSegments.last;
      expect(name, isNot(startsWith('fake_')));
      expect(name, isNot(startsWith('memory_')));
      if (file.path.contains('/presentation/') ||
          file.path.contains('/domain/')) {
        expect(source, isNot(contains('package:dio/')));
        expect(source, isNot(contains('package:objectbox/')));
      }
      expect(source, isNot(contains('GetIt')));
    }
  });

  test('consumer-owned files contain no structural plumbing', () {
    final root = _packageRoot('thin_consumer_canary');
    final lib = Directory('${root.path}/lib');
    final forbidden = <String>[
      'OwnedGraph',
      'ResourceTransaction',
      'DioOwner',
      'DriftDatabaseOwner',
      'ObjectBoxStoreOwner',
      'StreamSubscription',
      'CancelToken',
      'addListener(',
      'removeListener(',
      'Timer(',
    ];
    final generated = <File>[];
    for (final file
        in lib
            .listSync(recursive: true)
            .whereType<File>()
            .where((candidate) => candidate.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      if (file.path.endsWith('.dartitect.g.dart')) {
        generated.add(file);
        continue;
      }
      for (final marker in forbidden) {
        expect(
          source,
          isNot(contains(marker)),
          reason: '$marker is structural plumbing in ${file.path}',
        );
      }
    }
    final generatedSource = generated
        .map((file) => file.readAsStringSync())
        .join('\n');
    expect(generatedSource, contains('OwnedGraph'));
    expect(generatedSource, contains('ResourceTransaction'));
    expect(generatedSource, contains('DartitectAssemblyBinding'));
  });
}

Directory _packageRoot(String packageName) {
  var directory = Directory.current.absolute;
  while (true) {
    final config = File('${directory.path}/.dart_tool/package_config.json');
    if (config.existsSync()) {
      final json =
          jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
      final packages = json['packages']! as List<Object?>;
      final entry = packages.cast<Map<String, Object?>>().singleWhere(
        (candidate) => candidate['name'] == packageName,
      );
      return Directory.fromUri(config.uri.resolve(entry['rootUri']! as String));
    }
    if (directory.parent.path == directory.path) {
      throw StateError('Dart package configuration was not found.');
    }
    directory = directory.parent;
  }
}
