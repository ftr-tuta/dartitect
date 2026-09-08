import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import 'flutter_build_retry.dart';

const _sqliteDownload = '''
By default, this package downloads a pre-compiled SQLite library.
This failed (attepted to download https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.5.2/libsqlite3.x64.macos.dylib).
''';

void main() {
  for (final failure in <String>[
    '${_sqliteDownload}SocketException: Failed host lookup: github.com',
    '${_sqliteDownload}SocketException: Connection reset by peer',
    'CocoaPods: Response: 429',
    'CocoaPods: rate-limited due to too many requests',
  ]) {
    test(
      'recovers a diagnosed download and retains its diagnostics: $failure',
      () async {
        final delays = <Duration>[];
        final diagnostics = <String>[];
        var attempts = 0;
        final result = await retryFlutterBuildDownload(
          () async => ++attempts == 1
              ? ProcessResult(1, 1, '', failure)
              : ProcessResult(2, 0, 'build passed', ''),
          report: diagnostics.add,
          delay: (duration) async => delays.add(duration),
        );
        expect(result.exitCode, 0);
        expect(result.stdout, 'build passed');
        expect(attempts, 2);
        expect(delays, <Duration>[const Duration(seconds: 20)]);
        expect(diagnostics.first, contains(failure));
      },
    );
  }

  test(
    'persistent download failure stops after three total attempts',
    () async {
      final delays = <Duration>[];
      var attempts = 0;
      final result = await retryFlutterBuildDownload(
        () async => ProcessResult(
          ++attempts,
          255,
          '',
          '${_sqliteDownload}SocketException: Failed host lookup: github.com',
        ),
        report: (_) {},
        delay: (duration) async => delays.add(duration),
      );
      expect(result.exitCode, 255);
      expect(attempts, 3);
      expect(delays, <Duration>[
        const Duration(seconds: 20),
        const Duration(seconds: 40),
      ]);
    },
  );

  for (final failure in <String>[
    'Compiler error: Undefined name',
    'SocketException: Failed host lookup: another.example',
    '${_sqliteDownload}HTTP 403 Forbidden',
    '${_sqliteDownload}HandshakeException: certificate verification failed',
    '''${_sqliteDownload}SocketException: Failed host lookup: github.com
Hash of downloaded file differs from expected''',
    _sqliteDownload.replaceAll('sqlite3-3.5.2', 'sqlite3-9.9.9') +
        'SocketException: Connection reset by peer',
  ]) {
    test(
      'does not retry an unclassified or integrity failure: $failure',
      () async {
        var attempts = 0;
        final result = await retryFlutterBuildDownload(
          () async => ProcessResult(++attempts, 1, '', failure),
          report: (_) => fail('A terminal failure must not be retried.'),
          delay: (_) async => fail('A terminal failure must not wait.'),
        );
        expect(result.exitCode, 1);
        expect(attempts, 1);
      },
    );
  }

  test('a successful build does not retry download warnings', () async {
    var attempts = 0;
    final result = await retryFlutterBuildDownload(
      () async => ProcessResult(++attempts, 0, 'Response: 429', ''),
      report: (_) => fail('A successful build must not be retried.'),
    );
    expect(result.exitCode, 0);
    expect(attempts, 1);
  });

  test(
    'attempts and waits share the caller deadline without resetting it',
    () async {
      var elapsed = Duration.zero;
      var attempts = 0;
      final delays = <Duration>[];
      await expectLater(
        retryFlutterBuildDownload(
          () async {
            elapsed += attempts++ == 0
                ? const Duration(seconds: 690)
                : const Duration(seconds: 9);
            return ProcessResult(
              attempts,
              1,
              '',
              '${_sqliteDownload}SocketException: Connection reset by peer',
            );
          },
          report: (_) {},
          timeout: const Duration(minutes: 12),
          elapsed: () => elapsed,
          delay: (duration) async {
            delays.add(duration);
            elapsed += duration;
          },
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(attempts, 2);
      expect(delays, <Duration>[const Duration(seconds: 20)]);
    },
  );

  test('an expired deadline starts no build', () async {
    await expectLater(
      retryFlutterBuildDownload(
        () async => fail('An expired build must not start.'),
        report: (_) {},
        timeout: Duration.zero,
      ),
      throwsA(isA<TimeoutException>()),
    );
  });
}
