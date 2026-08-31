import 'dart:io';

import 'package:dartitect_cli/src/release/package_compatibility.dart';
import 'package:test/test.dart';

void main() {
  test(
    'accepts compatible mixed resolved versions without global equality',
    () async {
      final root = await Directory.systemTemp.createTemp('dartitect-lock-ok-');
      addTearDown(() => root.delete(recursive: true));
      final lock = File('${root.path}/pubspec.lock');
      await lock.writeAsString(
        _lock(<String, String>{
          'dartitect': '1.0.0-rc.10',
          'dartitect_cli': '1.0.0-rc.10',
        }),
      );

      expect(await DartitectLockCompatibility.inspect(lock), isEmpty);
    },
  );

  test('rejects a resolved package below the compatible baseline', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-lock-old-');
    addTearDown(() => root.delete(recursive: true));
    final lock = File('${root.path}/pubspec.lock');
    await lock.writeAsString(
      _lock(<String, String>{
        'dartitect': '1.0.0-rc.8',
        'dartitect_cli': '1.0.0-rc.10',
      }),
    );

    final findings = await DartitectLockCompatibility.inspect(lock);
    expect(findings, hasLength(1));
    expect(findings.single.package, 'dartitect');
    expect(findings.single.expectedRange, '>=1.0.0-rc.10 <1.0.0');
  });
}

String _lock(Map<String, String> versions) {
  final buffer = StringBuffer('packages:\n');
  for (final entry in versions.entries) {
    buffer
      ..writeln('  ${entry.key}:')
      ..writeln('    dependency: direct main')
      ..writeln('    description: ${entry.key}')
      ..writeln('    source: hosted')
      ..writeln('    version: "${entry.value}"');
  }
  return buffer.toString();
}
