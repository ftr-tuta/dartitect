import 'dart:io';

import 'package:test/test.dart';

import 'check_boundary_parity.dart';

void main() {
  test('isolated analyzer fixture does not depend on the Dio host cache', () {
    final pubspec = File('tool/analyzer_plugin_fixture/pubspec.yaml')
        .readAsStringSync();
    final lock = File('tool/analyzer_plugin_fixture/pubspec.lock')
        .readAsStringSync();

    expect(pubspec, contains('dio:\n    path: dependencies/dio'));
    expect(
      lock,
      contains(
        'path: "dependencies/dio"\n'
        '      relative: true\n'
        '    source: path\n'
        '    version: "5.11.0"',
      ),
    );
    expect(lock, isNot(contains('\n  mime:')));
  });

  test('normalizes native paths and analyzer file URIs identically', () async {
    final root = await Directory.systemTemp.createTemp('boundary-parity-');
    addTearDown(() => root.delete(recursive: true));
    final source = File(
      '${root.path}${Platform.pathSeparator}lib'
      '${Platform.pathSeparator}feature.dart',
    );
    await source.parent.create(recursive: true);
    await source.writeAsString('final feature = true;\n');

    expect(
      boundaryParityRelativePath(root, source.absolute.path),
      'lib/feature.dart',
    );
    expect(
      boundaryParityRelativePath(root, source.absolute.uri.toString()),
      'lib/feature.dart',
    );
    expect(
      boundaryParityRelativePath(
        root,
        source.absolute.path.replaceAll(
          Platform.pathSeparator,
          '${Platform.pathSeparator}${Platform.pathSeparator}',
        ),
      ),
      'lib/feature.dart',
    );
    expect(
      boundaryParityRelativePath(
        root,
        'lib${Platform.pathSeparator}feature.dart',
      ),
      'lib/feature.dart',
    );
    if (Platform.isWindows) {
      final uriWithLowercaseDrive = source.absolute.uri
          .toString()
          .replaceFirstMapped(
            RegExp(r'^file:///([A-Z]):'),
            (match) => 'file:///${match.group(1)!.toLowerCase()}:',
          );
      expect(
        boundaryParityRelativePath(root, uriWithLowercaseDrive),
        'lib/feature.dart',
      );
    }
  });

  test('uses canonical filesystem identity for containment', () async {
    if (Platform.isWindows) return;
    final parent = await Directory.systemTemp.createTemp('boundary-canonical-');
    final physical = Directory('${parent.path}/physical');
    final alias = Link('${parent.path}/alias');
    final source = File('${physical.path}/lib/feature.dart');
    addTearDown(() => parent.delete(recursive: true));
    await source.parent.create(recursive: true);
    await source.writeAsString('final feature = true;\n');
    await alias.create(physical.path);

    expect(
      boundaryParityRelativePath(Directory(alias.path), source.path),
      'lib/feature.dart',
    );
  });

  test('rejects analyzer paths outside the fixture', () async {
    final root = await Directory.systemTemp.createTemp('boundary-parity-');
    final outside = await Directory.systemTemp.createTemp(
      'boundary-parity-outside-',
    );
    addTearDown(() => root.delete(recursive: true));
    addTearDown(() => outside.delete(recursive: true));
    final outsideFile = File('${outside.path}/feature.dart');
    await outsideFile.writeAsString('final feature = false;\n');

    expect(
      () => boundaryParityRelativePath(root, outsideFile.uri.toString()),
      throwsFormatException,
    );
    expect(
      () => boundaryParityRelativePath(root, '../outside/feature.dart'),
      throwsFormatException,
    );
  });
}
