import 'dart:io';

import 'package:dartitect_api_compatibility_fixture/adapter_author_api.dart';
import 'package:dartitect_api_compatibility_fixture/application_api.dart';
import 'package:dartitect_api_compatibility_fixture/extension_author_api.dart';
import 'package:dartitect_api_compatibility_fixture/generated_api.dart';
import 'package:dartitect_api_compatibility_fixture/observability_1_0_api.dart';
import 'package:dartitect_api_compatibility_fixture/tooling_api.dart';
import 'package:test/test.dart';

void main() {
  test('all classified downstream audiences compile', () async {
    expect(applicationValue(applicationResult(7)), 7);
    await applicationOwner().disposeAsync();

    final extension = FixtureClockExtension();
    final clock = extension.build();
    extension.dispose(clock);
    expect(clock.isRunning, isFalse);

    expect(generatedBinding().isOwned, isTrue);
    expect(adapterRoute().value, '/tasks/{id}');
    expect(adapterTitectCodec().json.limits.maxBytes, 1048576);
    expect(contractTool(Directory.current), isNotNull);

    final observability = observabilityRuntimeFromOneDotZero();
    expect(await observability.flush(const Duration(seconds: 1)), isTrue);
    await observability.disposeAsync();
  });
}
