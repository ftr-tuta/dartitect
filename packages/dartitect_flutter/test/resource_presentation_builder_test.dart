import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('presentation builder is exhaustive, ticker-aware, and borrowed', (
    tester,
  ) async {
    final source = _QueueSource(<Object>[
      _snapshot(<int>[1]),
      _snapshot(<int>[]),
      'offline',
    ]);
    var resource = LiveResource<ResourceSnapshot<List<int>, String>, String>(
      source: source,
      policy: const ActivationPolicy.alwaysHot(),
    );
    var enabled = true;

    Widget tree() => Directionality(
      textDirection: TextDirection.ltr,
      child: TickerMode(
        enabled: enabled,
        child: ResourcePresentationBuilder<List<int>, String, String>(
          resource: resource,
          isEmpty: (value) => value.isEmpty,
          waiting: (_, state) => Text('waiting:${state.snapshot?.value}'),
          content: (_, state) => Text('content:${state.snapshot.value.join()}'),
          empty: (_, _) => const Text('empty'),
          failure: (_, state, cause) =>
              Text('failure:${cause.failure}:${state.snapshot?.value.join()}'),
          crashed: (_, state, cause) => Text(
            'crash:${cause.error.runtimeType}:${state.snapshot?.value.join()}',
          ),
        ),
      ),
    );

    await tester.pumpWidget(tree());
    await _pumpUntil(
      tester,
      () => find.text('content:1').evaluate().isNotEmpty,
    );
    source.latest.emit();
    await _pumpUntil(tester, () => find.text('empty').evaluate().isNotEmpty);

    enabled = false;
    await tester.pumpWidget(tree());
    source.latest.emit();
    await _pumpUntil(
      tester,
      () =>
          resource.state
              is ResourceFailed<ResourceSnapshot<List<int>, String>, String>,
    );
    expect(find.text('empty'), findsOneWidget);
    enabled = true;
    await tester.pumpWidget(tree());
    expect(find.text('failure:offline:'), findsOneWidget);

    expect(resource.isDisposed, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpUntil(tester, () => resource.observerCount == 0);
    expect(resource.isDisposed, isFalse);
    unawaited(resource.dispose());

    final crashSource = _QueueSource(<Object>[StateError('crash')]);
    resource = LiveResource<ResourceSnapshot<List<int>, String>, String>(
      source: crashSource,
      policy: const ActivationPolicy.alwaysHot(),
    );
    await tester.pumpWidget(tree());
    await _pumpUntil(
      tester,
      () => find.textContaining('crash:StateError').evaluate().isNotEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpUntil(tester, () => resource.observerCount == 0);
    unawaited(resource.dispose());
  });
}

ResourceSnapshot<List<int>, String> _snapshot(List<int> values) =>
    ResourceSnapshot<List<int>, String>(
      value: values,
      metadata: 'local',
      revision: values.length,
      observedAt: DateTime.utc(2026, 8, 31),
      isStale: false,
    );

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    await tester.pump();
    if (condition()) return;
  }
  fail('Condition did not settle.');
}

final class _QueueSource
    implements ReactiveSource<ResourceSnapshot<List<int>, String>, String> {
  _QueueSource(this.values);

  final List<Object> values;
  late _QueueSession latest;

  @override
  Future<
    Result<
      ReactiveSourceSession<ResourceSnapshot<List<int>, String>, String>,
      String
    >
  >
  open() async {
    latest = _QueueSession(this);
    return Ok<
      ReactiveSourceSession<ResourceSnapshot<List<int>, String>, String>
    >(latest);
  }

  Future<Result<ResourceSnapshot<List<int>, String>, String>> take() async {
    final value = values.removeAt(0);
    if (value is ResourceSnapshot<List<int>, String>) return Ok(value);
    if (value is String) return Err<String>(value, StackTrace.current);
    Error.throwWithStackTrace(value, StackTrace.current);
  }
}

final class _QueueSession
    implements
        ReactiveSourceSession<ResourceSnapshot<List<int>, String>, String> {
  _QueueSession(this.source);

  final _QueueSource source;
  final StreamController<void> _signals = StreamController<void>.broadcast(
    sync: true,
  );
  var _closed = false;

  @override
  Stream<void> get signals => _signals.stream;

  void emit() {
    if (!_closed) _signals.add(null);
  }

  @override
  Future<Result<ResourceSnapshot<List<int>, String>, String>> read(
    CancellationSignal signal,
  ) => source.take();

  @override
  Future<void> close() {
    if (_closed) return Future<void>.value();
    _closed = true;
    return _signals.close();
  }
}
