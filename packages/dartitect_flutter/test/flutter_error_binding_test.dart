import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chains and restores Flutter and platform handlers', () async {
    final reports = <FlutterCrashMechanism>[];
    final originalFlutter = FlutterError.onError;
    final originalPlatform = PlatformDispatcher.instance.onError;
    var flutterCalls = 0;
    var platformCalls = 0;
    FlutterError.onError = (_) => flutterCalls += 1;
    PlatformDispatcher.instance.onError = (_, _) {
      platformCalls += 1;
      return true;
    };

    final binding = FlutterErrorBinding.install(
      reporter: CallbackFlutterCrashReporter((_, _, mechanism) {
        reports.add(mechanism);
      }),
    );
    expect(
      () => FlutterErrorBinding.install(
        reporter: const NoOpFlutterCrashReporter(),
      ),
      throwsStateError,
    );

    FlutterError.onError!(
      FlutterErrorDetails(exception: StateError('framework')),
    );
    expect(
      PlatformDispatcher.instance.onError!(
        StateError('platform'),
        StackTrace.current,
      ),
      isTrue,
    );

    expect(flutterCalls, 1);
    expect(platformCalls, 1);
    expect(reports, hasLength(2));

    binding.dispose();
    binding.dispose();
    expect(FlutterError.onError, isNotNull);
    expect(PlatformDispatcher.instance.onError, isNotNull);

    FlutterError.onError = originalFlutter;
    PlatformDispatcher.instance.onError = originalPlatform;
  });

  test('guarded zone reports once and forwards the original error', () {
    final reports = <FlutterCrashMechanism>[];
    final forwarded = <Object>[];
    final binding = FlutterErrorBinding.install(
      reporter: CallbackFlutterCrashReporter((_, _, mechanism) {
        reports.add(mechanism);
      }),
    );

    binding.runGuarded(
      () => throw StateError('zone'),
      forward: (error, _) => forwarded.add(error),
    );

    expect(reports, hasLength(1));
    expect(reports.single, FlutterCrashMechanism.zone);
    expect(forwarded, hasLength(1));
    binding.dispose();
  });

  test('reporter failure does not replace chained Flutter handling', () {
    final original = FlutterError.onError;
    var chained = 0;
    FlutterError.onError = (_) => chained += 1;
    final binding = FlutterErrorBinding.install(
      reporter: CallbackFlutterCrashReporter(
        (_, _, _) => throw StateError('reporter'),
      ),
    );

    FlutterError.onError!(FlutterErrorDetails(exception: StateError('app')));

    expect(chained, 1);
    expect(binding.reporterFailureCount, 1);
    binding.dispose();
    FlutterError.onError = original;
  });
}
