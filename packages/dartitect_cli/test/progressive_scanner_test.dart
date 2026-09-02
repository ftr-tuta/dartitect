import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test('scan events are deterministic and scan collects completed', () async {
    final root = await Directory.systemTemp.createTemp('progressive-scan-');
    addTearDown(() => root.delete(recursive: true));
    await _write(root, 'pubspec.yaml', 'name: sample\n');
    await _write(root, 'lib/b.dart', 'class B {}\n');
    await _write(root, 'lib/a.dart', 'class A {}\n');
    final scanner = ProjectScanner(root);

    final events = await scanner.scanEvents().toList();
    final collected = await scanner.scan();

    expect(events.first, isA<ProjectScanStarted>());
    expect(events.last, isA<ProjectScanCompleted>());
    expect(
      events.whereType<ProjectScanFileDiscovered>().map((event) => event.path),
      <String>['lib/a.dart', 'lib/b.dart'],
    );
    expect(
      events.whereType<ProjectScanFileAnalyzed>().map((event) => event.path),
      <String>['lib/a.dart', 'lib/b.dart'],
    );
    expect(collected.dartFileCount, 2);
  });

  test(
    'source index hits, invalidates by content/config, and evicts LRU',
    () async {
      final root = await Directory.systemTemp.createTemp('source-index-');
      addTearDown(() => root.delete(recursive: true));
      await _write(root, 'pubspec.yaml', 'name: sample\n');
      await _write(root, 'lib/a.dart', 'class A {}\n');
      await _write(root, 'lib/b.dart', 'class B {}\n');
      final index = ProjectSourceIndex(capacity: 2);
      final scanner = ProjectScanner(root, sourceIndex: index);

      await scanner.scan();
      expect(index.missCount, 2);
      await scanner.scan();
      expect(index.hitCount, 2);

      await _write(root, 'lib/a.dart', 'class A { int value = 1; }\n');
      await scanner.scan();
      expect(index.missCount, 3);
      expect(index.hitCount, 3);

      await _write(root, 'dartitect.json', DartitectConfig().encode());
      await scanner.scan();
      expect(index.missCount, 5);

      final bounded = ProjectSourceIndex(capacity: 1);
      await ProjectScanner(root, sourceIndex: bounded).scan();
      expect(bounded.length, 1);
      expect(bounded.evictionCount, 1);
    },
  );

  test('cancellation emits one cancelled terminal without completed', () async {
    final root = await Directory.systemTemp.createTemp('cancelled-scan-');
    addTearDown(() => root.delete(recursive: true));
    await _write(root, 'pubspec.yaml', 'name: sample\n');
    for (var index = 0; index < 20; index += 1) {
      await _write(root, 'lib/file_$index.dart', 'class C$index {}\n');
    }
    final cancellation = CancellationSource();
    final events = <ProjectScanEvent>[];

    await for (final event in ProjectScanner(
      root,
    ).scanEvents(cancellation: cancellation.signal)) {
      events.add(event);
      if (event is ProjectScanStarted) cancellation.cancel('test');
    }

    expect(events.whereType<ProjectScanCancelled>(), hasLength(1));
    expect(events.whereType<ProjectScanCompleted>(), isEmpty);
  });

  test(
    'scan --jsonl emits schema-1 lines and preserves scan exit code',
    () async {
      final root = await Directory.systemTemp.createTemp('scan-jsonl-');
      addTearDown(() => root.delete(recursive: true));
      await _write(root, 'pubspec.yaml', 'name: sample\n');
      await _write(
        root,
        'lib/domain/model.dart',
        "import 'package:flutter/widgets.dart';\n",
      );
      final output = StringBuffer();
      final runner = DartitectCliRunner(
        currentDirectory: root,
        stdoutSink: output,
        stderrSink: StringBuffer(),
        interruptSignals: const Stream<Object?>.empty(),
      );

      final exitCode = await runner.run(<String>['scan', '--jsonl']);
      final lines = output
          .toString()
          .trim()
          .split('\n')
          .map((line) => jsonDecode(line) as Map<String, Object?>)
          .toList();

      expect(exitCode, 1);
      expect(lines.every((line) => line['schemaVersion'] == 1), isTrue);
      expect(lines.first['event'], 'started');
      expect(lines.last['event'], 'completed');
      expect(lines.map((line) => line['event']), contains('finding'));
    },
  );

  test('scan JSONL SIGINT emits cancelled and exits 130', () async {
    final root = await Directory.systemTemp.createTemp('scan-sigint-');
    addTearDown(() => root.delete(recursive: true));
    await _write(root, 'pubspec.yaml', 'name: sample\n');
    for (var index = 0; index < 40; index += 1) {
      await _write(root, 'lib/file_$index.dart', 'class C$index {}\n');
    }
    final interrupts = StreamController<Object?>();
    final output = StringBuffer();
    final runner = DartitectCliRunner(
      currentDirectory: root,
      stdoutSink: output,
      stderrSink: StringBuffer(),
      interruptSignals: interrupts.stream,
    );

    final running = runner.run(<String>['scan', '--jsonl']);
    interrupts.add(null);
    final exitCode = await running;
    final lines = output.toString().trim().split('\n');
    final terminal = jsonDecode(lines.last) as Map<String, Object?>;

    expect(exitCode, 130);
    expect(terminal['event'], 'cancelled');
    await interrupts.close();
  });

  test('JSONL is mutually exclusive with aggregate formats', () async {
    final errors = StringBuffer();
    final runner = DartitectCliRunner(
      stdoutSink: StringBuffer(),
      stderrSink: errors,
      interruptSignals: const Stream<Object?>.empty(),
    );

    expect(await runner.run(<String>['scan', '--jsonl', '--json']), 2);
    expect(await runner.run(<String>['scan', '--jsonl', '--sarif']), 2);
    expect(errors.toString(), contains('mutually exclusive'));
  });
}

Future<void> _write(Directory root, String path, String content) async {
  final file = File('${root.path}/$path');
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}
