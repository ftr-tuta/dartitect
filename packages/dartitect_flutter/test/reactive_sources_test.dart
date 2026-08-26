import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Future bridge runs initial and explicit refresh attempts', () async {
    var reads = 0;
    final resource = LiveResource<int, String>(
      source: FutureReactiveSource<int, String>((signal) async {
        signal.throwIfCancelled();
        return Ok<int>(++reads);
      }),
      policy: const ActivationPolicy.alwaysHot(),
    );

    await resource.start();
    await _flush();
    expect((resource.state as ResourceReady<int, String>).data, 1);
    expect(resource.refresh(), isTrue);
    await _flush();
    expect((resource.state as ResourceReady<int, String>).data, 2);
    await resource.dispose();
    expect(resource.activeOperationCount, 0);
  });

  test('Stream bridge publishes typed data and failure in order', () async {
    final controller = StreamController<Result<int, String>>();
    final resource = LiveResource<int, String>(
      source: StreamReactiveSource<int, String>(() => controller.stream),
      policy: const ActivationPolicy.alwaysHot(),
      backpressure: SourceBackpressure.everyEmission,
    );
    await resource.start();
    controller.add(const Ok<int>(1));
    await _flush();
    expect((resource.state as ResourceReady<int, String>).data, 1);

    controller.add(Err<String>('offline', StackTrace.current));
    await _flush();
    final failed = resource.state as ResourceFailed<int, String>;
    expect(failed.failure, 'offline');
    expect(failed.lastData, 1);

    await resource.dispose();
    await controller.close();
    expect(resource.activeOperationCount, 0);
  });

  test(
    'Stream bridge permits a fresh read after waiter cancellation',
    () async {
      final controller = StreamController<Result<int, String>>();
      final opened = await StreamReactiveSource<int, String>(
        () => controller.stream,
      ).open();
      final session = (opened as Ok<ReactiveSourceSession<int, String>>).value;
      final cancelled = CancellationSource();
      final firstRead = session.read(cancelled.signal);
      cancelled.cancel('superseded');

      await expectLater(firstRead, throwsA(isA<CancellationException>()));

      final next = session.read(CancellationSource().signal);
      controller.add(const Ok<int>(7));
      expect(await next, const Ok<int>(7));

      await session.close();
      await controller.close();
    },
  );

  test(
    'ValueListenable bridge reads initial state and detaches on dispose',
    () async {
      final notifier = _CountingNotifier<int>(1);
      final resource = LiveResource<int, String>(
        source: ValueListenableReactiveSource<int, String>(notifier),
        policy: const ActivationPolicy.alwaysHot(),
      );
      await resource.start();
      await _flush();
      expect((resource.state as ResourceReady<int, String>).data, 1);
      expect(notifier.listenerCount, 1);

      notifier.value = 2;
      await _flush();
      expect((resource.state as ResourceReady<int, String>).data, 2);

      await resource.dispose();
      expect(notifier.listenerCount, 0);
      notifier.dispose();
    },
  );
}

Future<void> _flush() async {
  for (var index = 0; index < 6; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _CountingNotifier<T> extends ChangeNotifier
    implements ValueListenable<T> {
  _CountingNotifier(this._value);

  T _value;
  int listenerCount = 0;

  @override
  T get value => _value;

  set value(T next) {
    _value = next;
    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    listenerCount += 1;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listenerCount -= 1;
    super.removeListener(listener);
  }
}
