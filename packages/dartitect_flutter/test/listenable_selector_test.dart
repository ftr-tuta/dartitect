import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('rebuilds only for a distinct selection and swaps sources', (
    tester,
  ) async {
    final first = _Model();
    final second = _Model()..count = 4;
    var builds = 0;

    Widget selector(_Model source) => Directionality(
      textDirection: TextDirection.ltr,
      child: ListenableSelector<_Model, int>(
        source: source,
        select: (model) => model.count,
        builder: (context, count, child) {
          builds += 1;
          return Text('$count');
        },
      ),
    );

    await tester.pumpWidget(selector(first));
    first.notifyWithoutChange();
    await tester.pump();
    expect(builds, 1);

    first.increment();
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    expect(builds, 2);

    await tester.pumpWidget(selector(second));
    expect(find.text('4'), findsOneWidget);
    first.increment();
    await tester.pump();
    expect(builds, 3);

    second.increment();
    await tester.pump();
    expect(find.text('5'), findsOneWidget);
    expect(builds, 4);
  });

  testWidgets('pauses offscreen and emits payload-free diagnostics', (
    tester,
  ) async {
    final model = _Model();
    final events = <FlutterBindingBuildEvent>[];
    var enabled = true;

    Widget tree() => Directionality(
      textDirection: TextDirection.ltr,
      child: TickerMode(
        enabled: enabled,
        child: ListenableSelector<_Model, int>(
          source: model,
          select: (source) => source.count,
          onBuild: (event) {
            events.add(event);
            throw StateError('observer failure is isolated');
          },
          builder: (context, count, child) => Text('$count'),
        ),
      ),
    );

    await tester.pumpWidget(tree());
    expect(events.single.kind, FlutterBindingKind.listenableSelector);
    expect(events.single.liveHandleCount, 1);
    expect(events.single.buildCount, 1);

    enabled = false;
    await tester.pumpWidget(tree());
    final pausedEvents = events.length;
    model.increment();
    await tester.pump();
    expect(events, hasLength(pausedEvents));

    enabled = true;
    await tester.pumpWidget(tree());
    expect(find.text('1'), findsOneWidget);
    expect(events.last.tickerEnabled, isTrue);
    expect(events.last.duration, isA<Duration>());
  });
}

final class _Model extends ChangeNotifier {
  int count = 0;

  void increment() {
    count += 1;
    notifyListeners();
  }

  void notifyWithoutChange() => notifyListeners();
}
