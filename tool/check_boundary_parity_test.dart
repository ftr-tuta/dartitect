import 'dart:io';

import 'package:test/test.dart';

import 'check_boundary_parity.dart';

void main() {
  test('normalizes native paths and analyzer file URIs identically', () async {
    final root = await Directory.systemTemp.createTemp('boundary-parity-');
    addTearDown(() => root.delete(recursive: true));
    final source = File(
      '${root.path}${Platform.pathSeparator}lib'
      '${Platform.pathSeparator}feature.dart',
    );

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

  test('rejects analyzer paths outside the fixture', () async {
    final root = await Directory.systemTemp.createTemp('boundary-parity-');
    final outside = await Directory.systemTemp.createTemp(
      'boundary-parity-outside-',
    );
    addTearDown(() => root.delete(recursive: true));
    addTearDown(() => outside.delete(recursive: true));

    expect(
      () => boundaryParityRelativePath(
        root,
        File('${outside.path}/feature.dart').uri.toString(),
      ),
      throwsFormatException,
    );
    expect(
      () => boundaryParityRelativePath(root, '../outside/feature.dart'),
      throwsFormatException,
    );
  });
}
