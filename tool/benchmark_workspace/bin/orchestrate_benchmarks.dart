import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main() async {
  final process = await Process.start(
    'flutter',
    <String>[
      'test',
      '--start-paused',
      '--machine',
      'benchmark/generate_benchmarks_test.dart',
    ],
    workingDirectory: Directory.current.path,
    runInShell: Platform.isWindows,
  );
  final resumed = Completer<void>();
  VmService? service;

  Future<void> consume(Stream<List<int>> stream, IOSink destination) async {
    await for (final line
        in stream.transform(utf8.decoder).transform(const LineSplitter())) {
      destination.writeln(line);
      final uri = _serviceUri(line);
      if (uri == null || resumed.isCompleted) continue;
      try {
        service = await vmServiceConnectUri(_webSocketUri(uri).toString());
        await _resumePausedIsolates(service!);
        resumed.complete();
      } catch (error, stackTrace) {
        resumed.completeError(error, stackTrace);
      }
    }
  }

  final output = consume(process.stdout, stdout);
  final errors = consume(process.stderr, stderr);
  final timeout = Timer(const Duration(seconds: 30), () {
    if (!resumed.isCompleted) {
      resumed.completeError(
        TimeoutException('Flutter test did not expose its VM service.'),
      );
      process.kill();
    }
  });
  try {
    await resumed.future;
    final code = await process.exitCode;
    await Future.wait<void>(<Future<void>>[output, errors]);
    if (code != 0) exitCode = code;
  } finally {
    timeout.cancel();
    await service?.dispose();
  }
}

Uri? _serviceUri(String line) {
  if (!line.contains('test.startedProcess')) return null;
  final decoded = jsonDecode(line);
  if (decoded is! List<Object?> || decoded.isEmpty) return null;
  final event = decoded.first! as Map<String, Object?>;
  final params = event['params']! as Map<String, Object?>;
  return Uri.parse(params['vmServiceUri']! as String);
}

Uri _webSocketUri(Uri serviceUri) {
  final path = serviceUri.path.endsWith('/')
      ? '${serviceUri.path}ws'
      : '${serviceUri.path}/ws';
  return serviceUri.replace(scheme: 'ws', path: path);
}

Future<void> _resumePausedIsolates(VmService service) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    final vm = await service.getVM();
    final isolates = vm.isolates ?? const <IsolateRef>[];
    if (isolates.isNotEmpty) {
      var resumed = 0;
      for (final reference in isolates) {
        final isolate = await service.getIsolate(reference.id!);
        final kind = isolate.pauseEvent?.kind;
        if (kind == EventKind.kPauseStart ||
            kind == EventKind.kPauseBreakpoint ||
            kind == EventKind.kPauseInterrupted) {
          await service.resume(reference.id!);
          resumed += 1;
        }
      }
      if (resumed > 0) return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('No paused Flutter test isolate was found.');
}
