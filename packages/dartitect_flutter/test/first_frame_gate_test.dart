import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('release and dispose allow a deferred frame exactly once', (
    tester,
  ) async {
    final binding = WidgetsBinding.instance;
    final owner = FirstFrameGate.defer(binding);
    expect(owner.isReleased, isFalse);

    owner.release();
    owner.release();
    owner.dispose();

    expect(owner.isReleased, isTrue);
    await tester.pump();
  });

  testWidgets('failure cleanup cannot leave the frame deferred', (
    tester,
  ) async {
    final owner = FirstFrameGate.defer(WidgetsBinding.instance);
    try {
      throw StateError('bootstrap failed');
    } on StateError {
      owner.dispose();
    }
    expect(owner.isReleased, isTrue);
    await tester.pump();
  });
}
