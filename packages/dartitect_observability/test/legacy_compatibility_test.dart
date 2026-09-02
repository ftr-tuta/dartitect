import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:test/test.dart';

void main() {
  test('legacy Redactor preserves its 1.0 projection behavior', () {
    final opaque = _LegacyOpaque();
    final key = _LegacyKey();
    final error = _LegacyError();
    const redactor = Redactor();

    expect(redactor.sanitize(opaque), '[_LegacyOpaque]');
    expect(opaque.toStringCalls, 0);

    final map = redactor.sanitize(<Object?, Object?>{key: 'safe'});
    expect(map, <String, Object?>{'[REDACTED_EMAIL]': '[REDACTED]'});
    expect(key.toStringCalls, 1);

    final redactedError = redactor.sanitizeError(error);
    expect(redactedError.type, '_LegacyError');
    expect(redactedError.message, r'$1[REDACTED]');
    expect(error.toStringCalls, 1);
  });

  test(
    'legacy runtime constructor and diagnostics remain source compatible',
    () async {
      final events = <LogEvent>[];
      final runtime = ObservabilityRuntime(
        logSinks: <LogSinkRegistration>[
          LogSinkRegistration.borrowed(CallbackLogSink(events.add)),
        ],
        allowedContextKeys: const <String>{'safe.count'},
        queueCapacity: 8,
        clock: () => DateTime.utc(2026),
      );

      runtime.logger.info(
        'legacy event',
        context: ObservabilityContext(
          attributes: const <String, Object?>{
            'safe.count': 2,
            'private.value': 'must not leave the runtime',
          },
        ),
      );

      expect(await runtime.flush(const Duration(seconds: 1)), isTrue);
      expect(events.single.message, 'legacy event');
      expect(events.single.timestamp, DateTime.utc(2026));
      expect(events.single.context.attributes, <String, Object?>{
        'safe.count': 2,
      });
      expect(runtime.diagnostics.deniedContextAttributes, 1);
      await runtime.disposeAsync();
      expect(runtime.isDisposed, isTrue);
    },
  );
}

final class _LegacyOpaque {
  int toStringCalls = 0;

  @override
  String toString() {
    toStringCalls += 1;
    return 'opaque secret';
  }
}

final class _LegacyKey {
  int toStringCalls = 0;

  @override
  String toString() {
    toStringCalls += 1;
    return 'person@example.com';
  }
}

final class _LegacyError {
  int toStringCalls = 0;

  @override
  String toString() {
    toStringCalls += 1;
    return 'token=secret';
  }
}
