import 'dart:io';

import 'package:dartitect_cli/src/release/package_compatibility.dart';
import 'package:test/test.dart';

const _ref = '1111111111111111111111111111111111111111';

void main() {
  test('accepts one canonical Git ref across the lockstep graph', () async {
    final lock = await _temporaryLock(<String, _Locked>{
      'dartitect': const _Locked(),
      'dartitect_cli': const _Locked(),
      'dartitect_flutter': const _Locked(),
    });

    expect(await DartitectLockCompatibility.inspect(lock), isEmpty);
  });

  test('rejects a future candidate outside the stable manifest', () async {
    final lock = await _temporaryLock(<String, _Locked>{
      'dartitect': const _Locked(version: '1.2.0-rc.1'),
      'dartitect_cli': const _Locked(version: '1.2.0-rc.1'),
      'dartitect_observability': const _Locked(version: '1.2.0-rc.1'),
    });

    final findings = await DartitectLockCompatibility.inspect(lock);

    expect(findings, hasLength(3));
    expect(
      findings.map((finding) => finding.reason),
      everyElement('version must be 1.1.0'),
    );
  });

  test('rejects a future candidate mixed with the stable cohort', () async {
    final lock = await _temporaryLock(<String, _Locked>{
      'dartitect': const _Locked(),
      'dartitect_observability': const _Locked(version: '1.2.0-rc.1'),
    });

    final findings = await DartitectLockCompatibility.inspect(lock);

    expect(findings, hasLength(1));
    expect(findings.single.reason, 'version must be 1.1.0');
  });

  test('rejects every non-canonical Git coordinate', () async {
    final lock = await _temporaryLock(<String, _Locked>{
      'dartitect': const _Locked(version: '1.1.1'),
      'dartitect_cli': const _Locked(source: 'hosted'),
      'dartitect_flutter': const _Locked(
        url: 'https://example.invalid/sdk.git',
      ),
      'dartitect_testing': const _Locked(path: 'packages/dartitect'),
      'dartitect_dio': const _Locked(tagPattern: 'v1.0.0'),
      'dartitect_drift': const _Locked(resolvedRef: 'short'),
    });

    final findings = await DartitectLockCompatibility.inspect(lock);
    final reasons = findings.map((item) => item.reason).toList();
    expect(reasons, contains('version must be 1.1.0'));
    expect(reasons, contains('source must be git'));
    expect(reasons, contains('Git URL is not canonical'));
    expect(reasons, contains('Git path must be packages/dartitect_testing'));
    expect(reasons, contains('tag-pattern must be v{{version}}'));
    expect(reasons, contains('resolved-ref must be a full Git SHA'));
    expect(
      findings.every((item) => item.expectedRange == '1.1.0 from v1.1.0'),
      isTrue,
    );
  });

  test('rejects different resolved refs inside the graph', () async {
    final lock = await _temporaryLock(<String, _Locked>{
      'dartitect': const _Locked(),
      'dartitect_cli': const _Locked(
        resolvedRef: '2222222222222222222222222222222222222222',
      ),
    });

    final findings = await DartitectLockCompatibility.inspect(lock);

    expect(findings, hasLength(2));
    expect(
      findings.map((item) => item.reason),
      everyElement(contains('differs from the lockstep graph')),
    );
  });

  test(
    'allows root entries only in the Dartitect development workspace',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'dartitect-lock-root-',
      );
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/tool/distribution_policy.json')
          .create(recursive: true);
      await File('${root.path}/packages/dartitect/pubspec.yaml')
          .create(recursive: true);
      final lock = File('${root.path}/pubspec.lock');
      await lock.writeAsString('''packages:
  dartitect:
    dependency: direct main
    description:
      name: dartitect
    source: root
    version: "1.0.0"
''');

      expect(await DartitectLockCompatibility.inspect(lock), isEmpty);
    },
  );
}

Future<File> _temporaryLock(Map<String, _Locked> entries) async {
  final root = await Directory.systemTemp.createTemp('dartitect-lock-');
  addTearDown(() => root.delete(recursive: true));
  final lock = File('${root.path}/pubspec.lock');
  final buffer = StringBuffer('packages:\n');
  for (final entry in entries.entries) {
    final value = entry.value;
    buffer
      ..writeln('  ${entry.key}:')
      ..writeln('    dependency: direct main');
    if (value.source == 'git') {
      buffer
        ..writeln('    description:')
        ..writeln('      path: ${value.path ?? 'packages/${entry.key}'}')
        ..writeln('      resolved-ref: "${value.resolvedRef}"')
        ..writeln('      tag-pattern: "${value.tagPattern}"')
        ..writeln('      url: "${value.url}"');
    } else {
      buffer.writeln('    description: ${entry.key}');
    }
    buffer
      ..writeln('    source: ${value.source}')
      ..writeln('    version: "${value.version}"');
  }
  await lock.writeAsString(buffer.toString());
  return lock;
}

final class _Locked {
  const _Locked({
    this.version = '1.1.0',
    this.source = 'git',
    this.url = 'https://github.com/ftr-tuta/dartitect.git',
    this.path,
    this.tagPattern = 'v{{version}}',
    this.resolvedRef = _ref,
  });

  final String version;
  final String source;
  final String url;
  final String? path;
  final String tagPattern;
  final String resolvedRef;
}
