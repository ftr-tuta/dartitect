import 'dart:convert';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Command0 completes without residual listeners', () async {
    const iterations = 10000;
    var notifications = 0;
    final command = Command0<int, StateError>(() async => const Ok<int>(1))
      ..addListener(() => notifications += 1);
    final watch = Stopwatch()..start();
    for (var index = 0; index < iterations; index += 1) {
      await command.execute();
      command.reset();
    }
    watch.stop();
    command.dispose();
    expect(command.isDisposed, isTrue);
    expect(notifications, iterations * 3);
    _printResult(
      'async_command_us_per_cycle',
      watch.elapsedMicroseconds / iterations,
    );
  });

  test('EffectChannel drains 10k effects without residual work', () async {
    const iterations = 10000;
    var delivered = 0;
    final effects = EffectChannel<int>(
      capacity: iterations,
      owner: EffectOwnerIdentity(
        kind: EffectOwnerKind.route,
        generation: Object(),
      ),
    );
    final subscription = effects.listen((_) => delivered += 1);
    final watch = Stopwatch()..start();
    for (var index = 0; index < iterations; index += 1) {
      expect(effects.sink.emit(index), EffectPublishResult.accepted);
    }
    while (effects.pendingCount != 0) {
      await Future<void>.delayed(Duration.zero);
    }
    watch.stop();

    expect(delivered, iterations);
    subscription.dispose();
    await effects.disposeAsync();
    expect(effects.pendingCount, 0);
    _printResult(
      'effect_channel_us_per_delivery',
      watch.elapsedMicroseconds / iterations,
    );
  });

  testWidgets('ViewModelHost and selector release every listener', (
    tester,
  ) async {
    const iterations = 200;
    var created = 0;
    var disposed = 0;
    final watch = Stopwatch()..start();
    for (var index = 0; index < iterations; index += 1) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ViewModelHost<_BenchmarkModel>.create(
            create: () {
              created += 1;
              return _BenchmarkModel(() => disposed += 1);
            },
            builder: (context, model) => ListenableSelector(
              source: model,
              select: (value) => value.value,
              builder: (context, value, child) => Text('$value'),
            ),
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
    watch.stop();
    expect(created, iterations);
    expect(disposed, iterations);
    _printResult(
      'view_model_selector_us_per_mount_cycle',
      watch.elapsedMicroseconds / iterations,
    );
  });
}

void _printResult(String name, double value) {
  // ignore: avoid_print
  print(jsonEncode(<String, double>{name: value}));
}

final class _BenchmarkModel extends ChangeNotifier implements Disposable {
  _BenchmarkModel(this._onDispose);

  final VoidCallback _onDispose;
  int value = 0;

  @override
  void dispose() {
    _onDispose();
    super.dispose();
  }
}
