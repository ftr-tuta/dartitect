import 'package:dartitect_flutter/dartitect_flutter_forms.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('form builder catches up after TickerMode resumes and borrows', (
    tester,
  ) async {
    final controller = DartitectFormController<String, String>(
      original: 'one',
      equals: (left, right) => left == right,
      submitter: (_, _) async => const Ok<void>(null),
    );
    var enabled = true;
    var builds = 0;

    Widget tree() => Directionality(
      textDirection: TextDirection.ltr,
      child: TickerMode(
        enabled: enabled,
        child: DartitectFormSnapshotBuilder<String, String>(
          controller: controller,
          builder: (_, snapshot, _) {
            builds += 1;
            return Text(snapshot.current);
          },
        ),
      ),
    );

    await tester.pumpWidget(tree());
    expect(find.text('one'), findsOneWidget);
    enabled = false;
    await tester.pumpWidget(tree());
    final pausedBuilds = builds;
    controller.update('two');
    await tester.pump();
    expect(builds, pausedBuilds);
    enabled = true;
    await tester.pumpWidget(tree());
    expect(find.text('two'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());

    expect(controller.snapshot.current, 'two');
    await controller.disposeAsync();
  });
}
