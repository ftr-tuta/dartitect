import 'dart:async';
import 'dart:io';

/// Retries only diagnosed transient downloads during a Flutter build.
///
/// The caller owns the overall deadline. CI retains its job deadline, and the
/// change-tax runner includes every attempt and delay in its existing deadline
/// and timing receipt. Compiler errors and integrity failures remain terminal.
Future<ProcessResult> retryFlutterBuildDownload(
  Future<ProcessResult> Function() build, {
  required void Function(String) report,
  Future<void> Function(Duration)? delay,
  Duration? timeout,
  Duration Function()? elapsed,
}) async {
  final wait = delay ?? Future<void>.delayed;
  final timer = Stopwatch()..start();
  Duration? remaining() {
    if (timeout == null) return null;
    final left = timeout - (elapsed?.call() ?? timer.elapsed);
    if (left <= Duration.zero) {
      throw TimeoutException('Flutter build deadline exhausted.', timeout);
    }
    return left;
  }

  for (var attempt = 1; ; attempt++) {
    final limit = remaining();
    final execution = build();
    final result = await (limit == null ? execution : execution.timeout(limit));
    if (result.exitCode == 0 ||
        attempt == 3 ||
        !_transientDownload('${result.stdout}\n${result.stderr}')) {
      return result;
    }
    // Keep the failed attempt visible instead of replacing its diagnostics.
    report('${result.stdout}\n${result.stderr}');
    final pause = Duration(seconds: attempt * 20);
    final available = remaining();
    if (available != null && available <= pause) {
      throw TimeoutException('No time remains for a build retry.', timeout);
    }
    report(
      'Flutter build dependency download failed transiently; '
      'retry ${attempt + 1}/3 in ${pause.inSeconds}s.',
    );
    final waiting = wait(pause);
    await (available == null ? waiting : waiting.timeout(available));
  }
}

bool _transientDownload(String output) {
  if (output.contains('Hash of downloaded file')) return false;
  // Preserve the existing bounded CocoaPods rate-limit recovery.
  if (output.contains('Response: 429') ||
      output.contains('rate-limited due to too many requests')) {
    return true;
  }
  return output.contains(
        'By default, this package downloads a pre-compiled '
        'SQLite library.',
      ) &&
      output.contains(
        'https://github.com/simolus3/sqlite3.dart/releases/'
        'download/sqlite3-3.5.2/',
      ) &&
      (output.contains('SocketException: Failed host lookup:') ||
          output.contains('SocketException: Connection reset by peer'));
}

Future<void> main(List<String> arguments) async {
  if (arguments.length < 3 ||
      arguments[0] != 'flutter' ||
      arguments[1] != 'build') {
    stderr.writeln(
      'Usage: dart run tool/flutter_build_retry.dart flutter build <build args>',
    );
    exitCode = 64;
    return;
  }
  final result = await retryFlutterBuildDownload(
    () => Process.run(
      'flutter',
      arguments.sublist(1),
      runInShell: Platform.isWindows,
    ),
    report: stderr.writeln,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  exitCode = result.exitCode;
}
