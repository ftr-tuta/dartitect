import 'package:dartitect_flutter/dartitect_flutter_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Material 3 preset classifies both axes at inclusive boundaries', () {
    const policy = DartitectLayoutBreakpoints.material3;

    expect(
      policy.classify(const Size(599, 479)),
      const DartitectWindowClass(
        width: DartitectSizeClass.compact,
        height: DartitectSizeClass.compact,
      ),
    );
    expect(
      policy.classify(const Size(600, 480)),
      const DartitectWindowClass(
        width: DartitectSizeClass.medium,
        height: DartitectSizeClass.medium,
      ),
    );
    expect(
      policy.classify(const Size(840, 900)),
      const DartitectWindowClass(
        width: DartitectSizeClass.expanded,
        height: DartitectSizeClass.expanded,
      ),
    );
  });

  test(
    'custom breakpoints reject negative, non-finite, and unordered values',
    () {
      expect(
        () => DartitectLayoutBreakpoints(mediumWidth: -1),
        throwsArgumentError,
      );
      expect(
        () => DartitectLayoutBreakpoints(expandedHeight: double.infinity),
        throwsArgumentError,
      );
      expect(
        () => DartitectLayoutBreakpoints(mediumWidth: 700, expandedWidth: 700),
        throwsArgumentError,
      );
    },
  );

  testWidgets('window builder reads MediaQuery and requires every branch', (
    tester,
  ) async {
    Widget tree(Size size) => MediaQuery(
      data: MediaQueryData(size: size),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: DartitectResponsiveWindowBuilder(
          compact: (_, windowClass) =>
              Text('compact:${windowClass.height.name}'),
          medium: (_, windowClass) => Text('medium:${windowClass.height.name}'),
          expanded: (_, windowClass) =>
              Text('expanded:${windowClass.height.name}'),
        ),
      ),
    );

    await tester.pumpWidget(tree(const Size(360, 640)));
    expect(find.text('compact:medium'), findsOneWidget);
    await tester.pumpWidget(tree(const Size(768, 1024)));
    expect(find.text('medium:expanded'), findsOneWidget);
    await tester.pumpWidget(tree(const Size(1024, 768)));
    expect(find.text('expanded:medium'), findsOneWidget);
  });

  testWidgets('region builder uses finite LayoutBuilder width', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 600,
            height: 480,
            child: DartitectResponsiveRegionBuilder(
              compact: (_, _) => const Text('compact'),
              medium: (_, windowClass) =>
                  Text('medium:${windowClass.height.name}'),
              expanded: (_, _) => const Text('expanded'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('medium:medium'), findsOneWidget);
  });

  testWidgets('region builder accepts an unbounded height', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 360,
              child: DartitectResponsiveRegionBuilder(
                compact: (_, windowClass) =>
                    Text('compact:${windowClass.height.name}'),
                medium: (_, _) => const Text('medium'),
                expanded: (_, _) => const Text('expanded'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('compact:compact'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
