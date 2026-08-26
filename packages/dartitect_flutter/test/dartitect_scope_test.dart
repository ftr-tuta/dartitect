import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reads nearest scope without reactive rebuilds', (tester) async {
    final outer = _Runtime('outer');
    final inner = _Runtime('inner');
    var builds = 0;

    await tester.pumpWidget(
      DartitectScope<_Runtime>(
        value: outer,
        child: DartitectScope<_Runtime>(
          value: inner,
          child: Builder(
            builder: (context) {
              builds += 1;
              return Text(
                DartitectScope.read<_Runtime>(context).name,
                textDirection: TextDirection.ltr,
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('inner'), findsOneWidget);
    expect(builds, 1);
  });

  testWidgets('maybeRead returns null and read explains a missing scope', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (value) {
          context = value;
          return const SizedBox();
        },
      ),
    );

    expect(DartitectScope.maybeRead<_Runtime>(context), isNull);
    expect(
      () => DartitectScope.read<_Runtime>(context),
      throwsA(isA<FlutterError>()),
    );
  });

  testWidgets('rejects retargeting an existing element to another identity', (
    tester,
  ) async {
    final firstIdentity = Object();
    await tester.pumpWidget(
      DartitectScope<_Runtime>(
        value: _Runtime('first', firstIdentity),
        child: const SizedBox(),
      ),
    );

    await tester.pumpWidget(
      DartitectScope<_Runtime>(
        value: _Runtime('second', Object()),
        child: const SizedBox(),
      ),
    );

    expect(tester.takeException(), isA<FlutterError>());
  });

  testWidgets('accepts a replacement facade with the same identity', (
    tester,
  ) async {
    final identity = Object();
    await tester.pumpWidget(
      DartitectScope<_Runtime>(
        value: _Runtime('first', identity),
        child: const SizedBox(),
      ),
    );
    await tester.pumpWidget(
      DartitectScope<_Runtime>(
        value: _Runtime('replacement facade', identity),
        child: const SizedBox(),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}

final class _Runtime implements DartitectScopeValue {
  _Runtime(this.name, [Object? identity])
    : scopeIdentity = identity ?? Object();

  final String name;

  @override
  final Object scopeIdentity;
}
