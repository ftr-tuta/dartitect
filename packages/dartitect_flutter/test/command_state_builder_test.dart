import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CommandState.match exposes all six complete variants', () {
    String render(CommandState<int, String> state) => state.match(
      idle: (value) => 'idle:${value.runningCount}',
      running: (value) => 'running:${value.runningCount}',
      success: (value) => 'success:${value.value}',
      failure: (value) => 'failure:${value.failure}',
      cancelled: (value) => 'cancelled:${value.reason}',
      crashed: (value) => 'crashed:${value.error}',
    );

    expect(render(const CommandIdleState<int, String>()), 'idle:0');
    expect(render(const CommandRunningState<int, String>()), 'running:1');
    expect(render(const CommandSuccessState<int, String>(7)), 'success:7');
    expect(
      render(CommandFailureState<int, String>('no', StackTrace.empty)),
      'failure:no',
    );
    expect(
      render(const CommandCancelledState<int, String>('stop')),
      'cancelled:stop',
    );
    expect(
      render(CommandCrashState<int, String>('boom', StackTrace.empty)),
      'crashed:boom',
    );
  });

  testWidgets('CommandStateBuilder is exhaustive and pauses under TickerMode', (
    tester,
  ) async {
    final completion = Completer<Result<int, String>>();
    final command = Command0<int, String>(() => completion.future);
    var enabled = true;
    var builds = 0;

    Widget tree() => Directionality(
      textDirection: TextDirection.ltr,
      child: TickerMode(
        enabled: enabled,
        child: CommandStateBuilder<int, String>(
          command: command,
          idle: (_, _) => Text('idle:${++builds}'),
          running: (_, state) =>
              Text('running:${state.runningCount}:${++builds}'),
          success: (_, state) => Text('success:${state.value}:${++builds}'),
          failure: (_, state) => Text('failure:${state.failure}:${++builds}'),
          cancelled: (_, state) =>
              Text('cancelled:${state.reason}:${++builds}'),
          crashed: (_, state) => Text('crashed:${state.error}:${++builds}'),
        ),
      ),
    );

    await tester.pumpWidget(tree());
    expect(find.textContaining('idle:'), findsOneWidget);
    unawaited(command.execute());
    await tester.pump();
    expect(find.textContaining('running:1:'), findsOneWidget);

    enabled = false;
    await tester.pumpWidget(tree());
    final pausedBuilds = builds;
    completion.complete(const Ok<int>(9));
    await tester.pump();
    expect(builds, pausedBuilds);

    enabled = true;
    await tester.pumpWidget(tree());
    expect(find.textContaining('success:9:'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await command.disposeAsync();
  });
}
