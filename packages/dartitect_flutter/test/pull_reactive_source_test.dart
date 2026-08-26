import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'merges triggers, pulls authoritative state, and closes in order',
    () async {
      final first = StreamController<void>.broadcast();
      final second = StreamController<void>.broadcast();
      final order = <String>[];
      var value = 0;
      final source = PullReactiveSource<int, StateError>(
        triggers: <PullInvalidationTrigger>[
          () => first.stream,
          () => second.stream,
        ],
        pull: (_) async => Ok<int>(++value),
        release: () => order.add('release'),
      );
      final opened = await source.open();
      final session =
          (opened as Ok<ReactiveSourceSession<int, StateError>>).value;
      final signals = <void>[];
      final subscription = session.signals.listen(signals.add);
      final cancellation = CancellationSource();

      expect(await session.read(cancellation.signal), const Ok<int>(1));
      first.add(null);
      second.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(signals, hasLength(2));

      await session.close();
      expect(order, <String>['release']);
      await subscription.cancel();
      await first.close();
      await second.close();
      cancellation.dispose();
    },
  );

  test('maps activation failure and rejects empty triggers', () async {
    expect(
      () => PullReactiveSource<int, StateError>(
        triggers: const <PullInvalidationTrigger>[],
        pull: (_) async => const Ok<int>(1),
      ),
      throwsArgumentError,
    );
    final source = PullReactiveSource<int, StateError>(
      triggers: <PullInvalidationTrigger>[
        () => throw StateError('watch failed'),
      ],
      pull: (_) async => const Ok<int>(1),
      mapOpenFailure: (error, _) => StateError(error.runtimeType.toString()),
    );

    expect(await source.open(), isA<Err<StateError>>());
  });
}
