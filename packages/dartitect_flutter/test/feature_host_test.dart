import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'FeatureHost publishes after start and disposes in reverse order',
    (tester) async {
      final events = <String>[];
      final start = Completer<void>();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: FeatureHost<String, String, _ViewModel>(
            parent: 'application',
            createGraph: (parent, transaction) {
              transaction.own(
                'resource',
                (_) => events.add('resource.dispose'),
              );
              return '$parent.feature';
            },
            createViewModel: (root) => _ViewModel(root, events),
            start: (viewModel) async {
              events.add('viewModel.start');
              await start.future;
            },
            loading: (_) => const Text('loading'),
            failure: (_, failure, retry) =>
                Text('failure:${failure.phase.name}'),
            ready: (_, root, viewModel) => Text('$root:${viewModel.root}'),
            onDisposed: () => events.add('host.disposed'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('loading'), findsOneWidget);
      start.complete();
      await tester.pumpAndSettle();
      expect(
        find.text('application.feature:application.feature'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(events, <String>[
        'viewModel.start',
        'viewModel.dispose',
        'resource.dispose',
        'host.disposed',
      ]);
    },
  );

  testWidgets('FeatureHost fences a late publication after unmount', (
    tester,
  ) async {
    final graph = Completer<String>();
    var viewModels = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FeatureHost<int, String, _ViewModel>(
          parent: 1,
          createGraph: (_, _) => graph.future,
          createViewModel: (root) {
            viewModels += 1;
            return _ViewModel(root, <String>[]);
          },
          loading: (_) => const Text('loading'),
          failure: (_, failure, retry) => const Text('failure'),
          ready: (_, root, viewModel) => const Text('ready'),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    graph.complete('late');
    await tester.pump();
    expect(viewModels, 1);
    expect(tester.takeException(), isNull);
  });
}

final class _ViewModel extends ChangeNotifier implements AsyncDisposable {
  _ViewModel(this.root, this.events);

  final String root;
  final List<String> events;

  @override
  Future<void> disposeAsync() async {
    events.add('viewModel.dispose');
    dispose();
  }
}
