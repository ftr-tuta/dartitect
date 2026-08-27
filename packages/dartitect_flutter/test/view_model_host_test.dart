import 'dart:async';

import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('create starts and disposes exactly once', (tester) async {
    final viewModel = _ViewModel();
    var creates = 0;
    var starts = 0;
    var builds = 0;

    await tester.pumpWidget(
      ViewModelHost<_ViewModel>.create(
        create: () {
          creates += 1;
          return viewModel;
        },
        start: (_) => starts += 1,
        builder: (context, value) {
          builds += 1;
          return const SizedBox();
        },
      ),
    );
    viewModel.notify();
    await tester.pump();

    expect(creates, 1);
    expect(starts, 1);
    expect(builds, 1, reason: 'The host must not listen to the view model.');

    await tester.pumpWidget(const SizedBox());
    expect(viewModel.disposeCalls, 1);
  });

  testWidgets('value replacement remains borrowed', (tester) async {
    final first = _ViewModel();
    final second = _ViewModel();

    Widget host(_ViewModel value) => Directionality(
      textDirection: TextDirection.ltr,
      child: ViewModelHost<_ViewModel>.value(
        value: value,
        builder: (context, current) => Text(current.name),
      ),
    );

    await tester.pumpWidget(host(first));
    await tester.pumpWidget(host(second));
    expect(find.text(second.name), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    expect(first.disposeCalls, 0);
    expect(second.disposeCalls, 0);
  });

  testWidgets('unmount during async start still disposes owned value', (
    tester,
  ) async {
    final started = Completer<void>();
    final viewModel = _ViewModel();

    await tester.pumpWidget(
      ViewModelHost<_ViewModel>.create(
        create: () => viewModel,
        start: (_) => started.future,
        builder: (context, value) => const SizedBox(),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    started.complete();
    await tester.pump();

    expect(viewModel.disposeCalls, 1);
  });

  testWidgets('asynchronous start failure is reported without gating build', (
    tester,
  ) async {
    final viewModel = _ViewModel();
    final failure = Completer<void>();

    await tester.pumpWidget(
      ViewModelHost<_ViewModel>.create(
        create: () => viewModel,
        start: (_) => failure.future,
        builder: (context, value) => const SizedBox(),
      ),
    );
    expect(tester.takeException(), isNull);
    failure.completeError(StateError('async start failed'), StackTrace.current);
    await tester.pump();

    expect(tester.takeException(), isA<StateError>());
    await tester.pumpWidget(const SizedBox());
    expect(viewModel.disposeCalls, 1);
  });

  testWidgets('created value retains its acquisition disposer', (tester) async {
    final viewModel = _ViewModel();
    final calls = <String>[];

    Widget host(String label) => ViewModelHost<_ViewModel>.create(
      create: () => viewModel,
      dispose: (_) => calls.add(label),
      builder: (context, value) => const SizedBox(),
    );

    await tester.pumpWidget(host('original'));
    await tester.pumpWidget(host('replacement callback'));
    await tester.pumpWidget(const SizedBox());

    expect(calls, <String>['original']);
  });

  testWidgets('synchronous start failure releases owned value', (tester) async {
    final viewModel = _ViewModel();

    await tester.pumpWidget(
      ViewModelHost<_ViewModel>.create(
        create: () => viewModel,
        start: (_) => throw StateError('start failed'),
        builder: (context, value) => const SizedBox(),
      ),
    );

    expect(tester.takeException(), isA<StateError>());
    expect(viewModel.disposeCalls, 1);
  });

  testWidgets('asynchronous disposal failure is reported', (tester) async {
    final viewModel = _ViewModel();

    await tester.pumpWidget(
      ViewModelHost<_ViewModel>.create(
        create: () => viewModel,
        dispose: (_) => Future<void>.error(
          StateError('async dispose failed'),
          StackTrace.current,
        ),
        builder: (context, value) => const SizedBox(),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(tester.takeException(), isA<StateError>());
  });

  testWidgets(
    'reassembly preserves the owner and refreshes compatible definitions',
    (tester) async {
      final viewModel = _ReactiveViewModel();
      final originalOwner = viewModel.owner;
      final originalComputed = viewModel.computed;
      var reassemblies = 0;

      await tester.pumpWidget(
        ViewModelHost<_ReactiveViewModel>.create(
          create: () => viewModel,
          onReassemble: (value) {
            reassemblies += 1;
            value.bind(factor: 3);
          },
          dispose: (value) => value.owner.dispose(),
          builder: (context, value) => const SizedBox(),
        ),
      );

      unawaited(tester.binding.reassembleApplication());
      await tester.pump();

      expect(reassemblies, 1);
      expect(viewModel.owner, same(originalOwner));
      expect(viewModel.computed, same(originalComputed));
      viewModel.owner.update<void>((write) => write.set(viewModel.input, 2));
      expect(viewModel.computed.value, 6);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(viewModel.owner.isDisposed, isTrue);
    },
  );

  testWidgets('reassembly reports an incompatible definition without reuse', (
    tester,
  ) async {
    final viewModel = _ReactiveViewModel();
    final originalComputed = viewModel.computed;

    await tester.pumpWidget(
      ViewModelHost<_ReactiveViewModel>.create(
        create: () => viewModel,
        onReassemble: (value) => value.bindIncompatible(),
        dispose: (value) => value.owner.dispose(),
        builder: (context, value) => const SizedBox(),
      ),
    );

    unawaited(tester.binding.reassembleApplication());
    await tester.pump();

    expect(tester.takeException(), isA<ReactiveKeyConflictException>());
    expect(viewModel.computed, same(originalComputed));
    viewModel.owner.update<void>((write) => write.set(viewModel.input, 2));
    expect(viewModel.computed.value, 4);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(viewModel.owner.isDisposed, isTrue);
  });
}

final class _ViewModel extends ChangeNotifier {
  final String name = 'view-model';
  int disposeCalls = 0;

  void notify() => notifyListeners();

  @override
  void dispose() {
    disposeCalls += 1;
    super.dispose();
  }
}

final class _ReactiveViewModel {
  _ReactiveViewModel() {
    bind(factor: 2);
  }

  final ReactiveOwner owner = ReactiveOwner();
  late final ReactiveValue<int> input = owner.value(1);
  late ReactiveComputed<int> computed;

  void bind({required int factor}) {
    computed = owner.computed<int>(
      const ReactiveKey<int>(
        'doubled',
        namespace: 'test.view-model-host',
        definitionRevision: 1,
        definitionFingerprint: 'multiply-v1',
      ),
      <ReactiveNode<Object?>>[input],
      (read) => read.read(input) * factor,
    );
  }

  void bindIncompatible() {
    owner.computed<int>(
      const ReactiveKey<int>(
        'doubled',
        namespace: 'test.view-model-host',
        definitionRevision: 2,
        definitionFingerprint: 'multiply-v2',
      ),
      <ReactiveNode<Object?>>[input],
      (read) => read.read(input) * 3,
    );
  }
}
