import 'package:dartitect/dartitect.dart';
import 'package:test/test.dart';

void main() {
  test(
    'owned bindings release in reverse and borrowed values survive',
    () async {
      final events = <String>[];
      final borrowed = Object();
      final first = Object();
      final second = Object();

      final graph = await ResourceTransaction.create((transaction) {
        final borrowedValue = DartitectAssemblyBinding<Object>.borrowed(
          borrowed,
        ).bind(transaction);
        final firstValue = DartitectAssemblyBinding<Object>.owned(
          first,
          release: (_) => events.add('first'),
          label: 'first',
        ).bind(transaction);
        final secondValue = DartitectAssemblyBinding<Object>.owned(
          second,
          release: (_) => events.add('second'),
          label: 'second',
        ).bind(transaction);
        return <Object>[borrowedValue, firstValue, secondValue];
      });

      await graph.disposeAsync();

      expect(graph.root, <Object>[borrowed, first, second]);
      expect(events, <String>['second', 'first']);
    },
  );

  test('binding is single-use and labels are actively validated', () async {
    final binding = DartitectAssemblyBinding<Object>.borrowed(Object());
    final transaction = ResourceTransaction();
    binding.bind(transaction);

    expect(() => binding.bind(transaction), throwsStateError);
    expect(
      () => DartitectAssemblyBinding<Object>.owned(
        Object(),
        release: (_) {},
        label: ' ',
      ),
      throwsArgumentError,
    );
    await transaction.rollback();
  });
}
