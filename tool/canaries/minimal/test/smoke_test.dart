import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_minimal_packaged_canary/main.dart';
import 'package:dartitect_minimal_packaged_canary/profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'constructor composition, generated model, command, and teardown pass',
    () async {
      const initial = Profile(id: '1', label: 'initial');
      expect(
        initial.copyWith(label: 'packaged'),
        const Profile(id: '1', label: 'packaged'),
      );
      expect(
        initial.copyWith(clearLabel: true),
        const Profile(id: '1', label: null),
      );

      final root = CompositionRoot();
      final outcome = await root.profile.load.execute();
      expect(outcome, isA<CommandExecutionSucceeded<String, String>>());
      await root.disposeAsync();
      expect(root.profile.load.isDisposed, isTrue);
    },
  );
}
