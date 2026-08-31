import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_flutter/dartitect_flutter_forms.dart';
import 'package:dartitect_flutter/dartitect_flutter_queries.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paved_road_canary/presentation/ui_quality_state_gallery.dart';

void main() {
  testWidgets('gallery covers loading stale empty expected failure and crash', (
    tester,
  ) async {
    final commandPort = _CommandPort();
    final command = Command0<String, String>(commandPort.run);
    final form = DartitectFormController<String, String>(
      original: 'original',
      equals: (left, right) => left == right,
      submitter: (value, cancellation) async => const Ok<void>(null),
    );
    final queryPort = _QueryPort();
    final query = DartitectQueryController<String, String, String>(
      initialQuery: 'all',
      port: queryPort,
      identity: (value) => value,
    );
    final resourceSource = _ResourceSource();
    final resource = LiveResource<ResourceSnapshot<List<String>, int>, String>(
      source: resourceSource,
      policy: const ActivationPolicy.alwaysHot(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanaryStateGallery(
            command: command,
            form: form,
            query: query,
            resource: resource,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('command idle'), findsOneWidget);
    expect(find.text('form original'), findsOneWidget);
    expect(find.text('query initial'), findsOneWidget);
    expect(find.text('resource loading'), findsOneWidget);

    final firstCommand = command.execute();
    await tester.pump();
    expect(find.text('command loading'), findsOneWidget);
    commandPort.complete(const Ok<String>('done'));
    await firstCommand;
    await tester.pump();
    expect(find.text('command success done'), findsOneWidget);

    final failedCommand = command.execute();
    commandPort.complete(Err<String>('offline', StackTrace.current));
    await failedCommand;
    await tester.pump();
    expect(find.text('command expected failure offline'), findsOneWidget);

    final crashedCommand = command.execute();
    commandPort.crash(StateError('synthetic crash'));
    await expectLater(crashedCommand, throwsA(isA<StateError>()));
    await tester.pump();
    expect(find.text('command crash StateError'), findsOneWidget);

    form.update('edited');
    await tester.pump();
    expect(find.text('form edited'), findsOneWidget);

    final emptyRefresh = query.refresh();
    await tester.pump();
    expect(find.text('query loading'), findsOneWidget);
    queryPort.complete(<String>[]);
    await emptyRefresh;
    await tester.pump();
    expect(find.text('query empty'), findsOneWidget);

    final contentRefresh = query.refresh();
    queryPort.complete(<String>['cached']);
    await contentRefresh;
    await tester.pump();
    expect(find.text('query content cached'), findsOneWidget);
    final failedRefresh = query.refresh();
    await tester.pump();
    expect(find.text('query loading stale cached'), findsOneWidget);
    queryPort.fail('offline');
    await failedRefresh;
    await tester.pump();
    expect(
      find.text('query expected failure offline stale cached'),
      findsOneWidget,
    );

    resourceSource.complete(_snapshot(<String>['cached']));
    await _pumpUntil(tester, 'resource content cached');
    resourceSource.emit(_snapshot(<String>[]));
    await _pumpUntil(tester, 'resource empty');
    resourceSource.emit('offline');
    await _pumpUntil(tester, 'resource expected failure offline stale');
    resourceSource.emit(StateError('synthetic crash'));
    await _pumpUntil(tester, 'resource crash StateError');

    await tester.pumpWidget(const SizedBox.shrink());
    await command.disposeAsync();
    await form.disposeAsync();
    await query.disposeAsync();
    unawaited(resource.dispose());
  });
}

ResourceSnapshot<List<String>, int> _snapshot(List<String> values) =>
    ResourceSnapshot<List<String>, int>(
      value: values,
      metadata: values.length,
      revision: values.length,
      observedAt: DateTime.utc(2026, 8, 31),
      isStale: false,
    );

Future<void> _pumpUntil(WidgetTester tester, String text) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    await tester.pump();
    if (find.text(text).evaluate().isNotEmpty) return;
  }
  fail('Did not render "$text".');
}

final class _CommandPort {
  Completer<Result<String, String>>? _pending;

  Future<Result<String, String>> run() {
    _pending = Completer<Result<String, String>>();
    return _pending!.future;
  }

  void complete(Result<String, String> result) => _pending!.complete(result);

  void crash(Object error) =>
      _pending!.completeError(error, StackTrace.current);
}

final class _QueryPort implements DartitectQueryPort<String, String, String> {
  Completer<Result<DartitectQueryPage<String>, String>>? _pending;

  @override
  bool get localAuthority => false;

  @override
  Future<Result<DartitectQueryPage<String>, String>> fetch(
    String query, {
    required String? cursor,
    required CancellationSignal cancellation,
  }) {
    _pending = Completer<Result<DartitectQueryPage<String>, String>>();
    return _pending!.future;
  }

  void complete(List<String> items) => _pending!.complete(
    Ok<DartitectQueryPage<String>>(
      DartitectQueryPage<String>(items: items, nextCursor: null),
    ),
  );

  void fail(String failure) =>
      _pending!.complete(Err<String>(failure, StackTrace.current));

  @override
  Stream<List<String>> watchLocal(String query) => const Stream.empty();
}

final class _ResourceSource
    implements ReactiveSource<ResourceSnapshot<List<String>, int>, String> {
  Completer<Result<ResourceSnapshot<List<String>, int>, String>>? _pending;
  late _ResourceSession _session;

  @override
  Future<
    Result<
      ReactiveSourceSession<ResourceSnapshot<List<String>, int>, String>,
      String
    >
  >
  open() async {
    _session = _ResourceSession(this);
    return Ok<
      ReactiveSourceSession<ResourceSnapshot<List<String>, int>, String>
    >(_session);
  }

  Future<Result<ResourceSnapshot<List<String>, int>, String>> read() {
    _pending = Completer<Result<ResourceSnapshot<List<String>, int>, String>>();
    return _pending!.future;
  }

  void complete(ResourceSnapshot<List<String>, int> snapshot) {
    _pending!.complete(Ok<ResourceSnapshot<List<String>, int>>(snapshot));
  }

  void emit(Object value) {
    _session.next = value;
    _session.emit();
  }
}

final class _ResourceSession
    implements
        ReactiveSourceSession<ResourceSnapshot<List<String>, int>, String> {
  _ResourceSession(this.source);

  final _ResourceSource source;
  final StreamController<void> _signals = StreamController<void>.broadcast(
    sync: true,
  );
  Object? next;

  @override
  Stream<void> get signals => _signals.stream;

  void emit() => _signals.add(null);

  @override
  Future<Result<ResourceSnapshot<List<String>, int>, String>> read(
    CancellationSignal signal,
  ) async {
    final value = next;
    if (value == null) return source.read();
    next = null;
    if (value is ResourceSnapshot<List<String>, int>) return Ok(value);
    if (value is String) return Err<String>(value, StackTrace.current);
    Error.throwWithStackTrace(value, StackTrace.current);
  }

  @override
  Future<void> close() => _signals.close();
}
