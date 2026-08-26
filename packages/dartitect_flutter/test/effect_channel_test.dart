import 'dart:async';

import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  EffectChannel<_Effect> channel({int capacity = 4}) => EffectChannel<_Effect>(
    capacity: capacity,
    owner: EffectOwnerIdentity(
      kind: EffectOwnerKind.route,
      generation: Object(),
    ),
  );

  test(
    'queues before attach and delivers accepted effects once in FIFO',
    () async {
      final effects = channel();
      expect(effects.sink.emit(const _Effect(1)), EffectPublishResult.accepted);
      expect(effects.sink.emit(const _Effect(2)), EffectPublishResult.accepted);
      final delivered = <int>[];

      final subscription = effects.listen((effect) => delivered.add(effect.id));
      await Future<void>.delayed(Duration.zero);

      expect(delivered, <int>[1, 2]);
      expect(effects.pendingCount, 0);
      subscription.dispose();
      await effects.disposeAsync();
    },
  );

  test(
    'rejects overflow, a second consumer, and post-disposal emission',
    () async {
      final effects = channel(capacity: 1);
      expect(effects.sink.emit(const _Effect(1)), EffectPublishResult.accepted);
      expect(effects.sink.emit(const _Effect(2)), EffectPublishResult.full);
      final subscription = effects.listen((_) {});
      expect(() => effects.listen((_) {}), throwsStateError);
      subscription.dispose();
      await effects.disposeAsync();
      expect(effects.sink.emit(const _Effect(3)), EffectPublishResult.disposed);
    },
  );

  test('reports consumer failure once and never replays the effect', () async {
    final reporter = _Reporter();
    final effects = EffectChannel<_Effect>(
      capacity: 2,
      owner: EffectOwnerIdentity(
        kind: EffectOwnerKind.application,
        generation: Object(),
      ),
      reporter: reporter,
    );
    effects.sink.emit(const _Effect(1));
    final first = effects.listen((_) => throw StateError('listener failed'));
    await Future<void>.delayed(Duration.zero);
    first.dispose();
    final delivered = <_Effect>[];
    final second = effects.listen(delivered.add);
    await Future<void>.delayed(Duration.zero);

    expect(reporter.errors, hasLength(1));
    expect(delivered, isEmpty);
    second.dispose();
    await effects.disposeAsync();
  });

  test('detach and reattach preserves one pending FIFO delivery', () async {
    final effects = channel();
    final delivered = <int>[];
    final first = effects.listen((effect) => delivered.add(effect.id));
    first.dispose();
    expect(effects.sink.emit(const _Effect(4)), EffectPublishResult.accepted);

    final second = effects.listen((effect) => delivered.add(effect.id));
    await Future<void>.delayed(Duration.zero);

    expect(delivered, <int>[4]);
    second.dispose();
    await effects.disposeAsync();
  });

  test(
    'dispose waits for the active callback and discards queued effects',
    () async {
      final effects = channel();
      final callbackStarted = Completer<void>();
      final callbackGate = Completer<void>();
      final subscription = effects.listen((_) async {
        callbackStarted.complete();
        await callbackGate.future;
      });
      effects.sink.emit(const _Effect(1));
      effects.sink.emit(const _Effect(2));
      await callbackStarted.future;

      var disposed = false;
      final disposal = effects.disposeAsync().then((_) => disposed = true);
      await Future<void>.delayed(Duration.zero);
      expect(disposed, isFalse);
      expect(effects.pendingCount, 1);
      expect(effects.sink.emit(const _Effect(3)), EffectPublishResult.disposed);

      callbackGate.complete();
      await disposal;
      expect(effects.pendingCount, 0);
      subscription.dispose();
    },
  );

  testWidgets('EffectListener uses only its currently mounted context', (
    tester,
  ) async {
    final effects = channel();
    final delivered = <String>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: EffectListener<_Effect>(
          channel: effects,
          onEffect: (context, effect) {
            delivered.add('${Directionality.of(context).name}:${effect.id}');
          },
          child: const SizedBox(),
        ),
      ),
    );

    effects.sink.emit(const _Effect(7));
    await tester.pump();
    expect(delivered, <String>['ltr:7']);

    await tester.pumpWidget(const SizedBox());
    effects.sink.emit(const _Effect(8));
    await tester.pump();
    expect(delivered, <String>['ltr:7']);
    await effects.disposeAsync();
  });

  testWidgets('EffectListener swaps route channels without stale delivery', (
    tester,
  ) async {
    final oldChannel = channel();
    final nextChannel = channel();
    final delivered = <int>[];

    Widget listener(EffectChannel<_Effect> effects) => Directionality(
      textDirection: TextDirection.ltr,
      child: EffectListener<_Effect>(
        channel: effects,
        onEffect: (_, effect) => delivered.add(effect.id),
        child: const SizedBox(),
      ),
    );

    await tester.pumpWidget(listener(oldChannel));
    await tester.pumpWidget(listener(nextChannel));
    oldChannel.sink.emit(const _Effect(1));
    nextChannel.sink.emit(const _Effect(2));
    await tester.pump();

    expect(delivered, <int>[2]);
    await tester.pumpWidget(const SizedBox());
    await oldChannel.disposeAsync();
    await nextChannel.disposeAsync();
  });
}

final class _Effect {
  const _Effect(this.id);

  final int id;
}

final class _Reporter implements EffectErrorReporter {
  final List<Object> errors = <Object>[];

  @override
  void report(Object error, StackTrace stackTrace) => errors.add(error);
}
