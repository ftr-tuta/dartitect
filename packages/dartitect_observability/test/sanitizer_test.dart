import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:test/test.dart';

void main() {
  test('structured diagnostic input is immutable and destination-aware', () {
    final sanitizer = _diagnosticSanitizer();
    final input = <String, Object?>{
      'status': 'ready',
      'email': 'person@example.com',
      'authorization': 'Bearer top-secret',
      'nested': <String, Object?>{
        'message': 'contact person@example.com?token=secret',
      },
    };

    final local = sanitizer.prepare(
      ObservabilityClassifiedValue<Object?>(
        input,
        classes: <ObservabilityDataClass>{ObservabilityDataClass.httpBody},
      ),
      destination: ObservabilityDestinationKind.local,
    );
    final remote = sanitizer.prepare(
      ObservabilityClassifiedValue<Object?>(
        input,
        classes: <ObservabilityDataClass>{ObservabilityDataClass.httpBody},
      ),
      destination: ObservabilityDestinationKind.remote,
    );

    expect('${local.value}', isNot(contains('top-secret')));
    expect('${local.value}', isNot(contains('person@example.com')));
    expect('${remote.value}', isNot(contains('top-secret')));
    expect('${remote.value}', isNot(contains('person@example.com')));
    expect(local.diagnostics.deniedValues, greaterThan(0));
    expect(local.diagnostics.allowedValues, greaterThan(0));
    expect(local.value, isA<Map<String, Object?>>());
    expect(
      () => (local.value! as Map<String, Object?>)['new'] = 'value',
      throwsUnsupportedError,
    );
  });

  test('new path never stringifies arbitrary errors, keys, or values', () {
    final error = _ExplosiveError();
    final key = _ExplosiveKey();
    final value = _ExplosiveValue();
    final sanitizer = _diagnosticSanitizer();

    final preparedError = sanitizer.prepareError(
      error,
      destination: ObservabilityDestinationKind.local,
    );
    final preparedMap = sanitizer.prepare(
      ObservabilityClassifiedValue<Object?>(
        <Object?, Object?>{key: value},
        classes: <ObservabilityDataClass>{ObservabilityDataClass.httpBody},
      ),
      destination: ObservabilityDestinationKind.local,
    );

    expect(error.toStringCalls, 0);
    expect(key.toStringCalls, 0);
    expect(value.toStringCalls, 0);
    expect('${preparedError.value}', contains('_ExplosiveError'));
    expect('${preparedMap.value}', isNot(contains('private')));
  });

  test('cycles and masked key collisions use stable data-free markers', () {
    final cyclic = <String, Object?>{};
    cyclic['self'] = cyclic;
    final input = LinkedHashMap<Object?, Object?>()
      ..['email'] = 'first@example.com'
      ..['user_email'] = 'second@example.com'
      ..['cycle'] = cyclic;
    final result = _diagnosticSanitizer().prepare(
      ObservabilityClassifiedValue<Object?>(
        input,
        classes: <ObservabilityDataClass>{ObservabilityDataClass.httpBody},
      ),
      destination: ObservabilityDestinationKind.local,
    );

    expect('${result.value}', contains('[MASKED_KEY_1]'));
    expect('${result.value}', contains('[MASKED_KEY_2]'));
    expect('${result.value}', contains('[CYCLE]'));
    expect(result.diagnostics.cycles, 1);
  });

  test('global budgets and Unicode truncation are deterministic', () {
    final sanitizer = ObservabilitySanitizer(
      policy: ObservabilityPrivacyPolicy.fromProfile(
        profile: ObservabilityPrivacyProfile.diagnostic,
        overrideRuleAllow: <ObservabilityDataClass>{
          ObservabilityDataClass.safeMetadata,
          ObservabilityDataClass.httpBody,
        },
      ),
      limits: const ObservabilitySanitizationLimits(
        maxDepth: 3,
        maxCollectionLength: 3,
        maxStringCodePoints: 3,
        maxNodes: 6,
        maxTotalTextCodePoints: 5,
        maxStackFrames: 2,
        maxClassificationWork: 40,
      ),
    );
    final result = sanitizer.prepare(
      ObservabilityClassifiedValue<Object?>(
        'A😀BC',
        classes: <ObservabilityDataClass>{ObservabilityDataClass.safeMetadata},
      ),
      destination: ObservabilityDestinationKind.local,
    );
    final collection = sanitizer.prepare(
      ObservabilityClassifiedValue<Object?>(
        <int>[1, 2, 3, 4],
        classes: <ObservabilityDataClass>{ObservabilityDataClass.httpBody},
      ),
      destination: ObservabilityDestinationKind.local,
    );

    expect(result.value, 'A😀B…[TRUNCATED]');
    expect(result.diagnostics.textCodePoints, lessThanOrEqualTo(5));
    expect(result.diagnostics.visitedNodes, lessThanOrEqualTo(6));
    expect(result.diagnostics.truncatedText, greaterThan(0));
    expect(collection.diagnostics.truncatedCollections, 1);
  });

  test('explicit projectors are the only unknown-object projection path', () {
    final sanitizer = ObservabilitySanitizer(
      policy: ObservabilityPrivacyPolicy.fromProfile(
        profile: ObservabilityPrivacyProfile.diagnostic,
      ),
      projectors: <ObservabilityValueProjector>[_SafeIdProjector()],
    );
    final projected = sanitizer.prepare(
      _SafeId(42),
      destination: ObservabilityDestinationKind.local,
    );

    expect(projected.value, '[REDACTED]');
  });

  test('only explicit stack projections consume the frame budget', () {
    final sanitizer = ObservabilitySanitizer(
      policy: ObservabilityPrivacyPolicy.fromProfile(
        profile: ObservabilityPrivacyProfile.diagnostic,
      ),
      limits: const ObservabilitySanitizationLimits(maxStackFrames: 2),
    );
    final raw = sanitizer.prepareStackTrace(
      _ExplosiveStackTrace(),
      destination: ObservabilityDestinationKind.local,
    );
    final explicit = sanitizer.prepareStackTrace(
      const ObservabilityStackTraceProjection(
        '#0 file:///home/person/private.dart:1\n'
        '#1 package:app/main.dart:2\n'
        '#2 package:app/next.dart:3',
      ),
      destination: ObservabilityDestinationKind.local,
    );

    expect(raw.value, '[STACK_TRACE_OMITTED]');
    expect(explicit.value, hasLength(2));
    expect('${explicit.value}', isNot(contains('/home/person')));
    expect(explicit.diagnostics.stackFrames, 2);
    expect(explicit.diagnostics.truncatedFrames, 1);
  });

  test('custom classifiers fail closed without retaining partial classes', () {
    final throwing = ObservabilitySanitizer(
      policy: ObservabilityPrivacyPolicy.fromProfile(
        profile: ObservabilityPrivacyProfile.diagnostic,
      ),
      classifiers: <ObservabilityDataClassifier>[_PartialThrowClassifier()],
    ).prepare('safe-looking', destination: ObservabilityDestinationKind.local);
    final exhausted = ObservabilitySanitizer(
      policy: ObservabilityPrivacyPolicy.fromProfile(
        profile: ObservabilityPrivacyProfile.diagnostic,
      ),
      classifiers: <ObservabilityDataClassifier>[_ManyClassesClassifier()],
      limits: const ObservabilitySanitizationLimits(maxClassificationWork: 3),
    ).prepare('safe-looking', destination: ObservabilityDestinationKind.local);

    expect(throwing.value, '[DENIED]');
    expect(throwing.diagnostics.classifierFailures, 1);
    expect(exhausted.value, '[DENIED]');
    expect(exhausted.diagnostics.truncatedClassification, greaterThan(0));
  });

  test('binary values become metadata without iterating their contents', () {
    final sanitizer = _diagnosticSanitizer();
    final bytes = Uint8List.fromList(<int>[115, 101, 99, 114, 101, 116]);
    final typed = Int16List.fromList(<int>[1, 2, 3]);
    final stream = StreamController<List<int>>.broadcast(sync: true);
    addTearDown(stream.close);

    expect(
      sanitizer.sanitize(
        bytes,
        destination: ObservabilityDestinationKind.local,
      ),
      <String, Object?>{'kind': 'uint8_list', 'length': 6},
    );
    expect(
      sanitizer.sanitize(
        typed,
        destination: ObservabilityDestinationKind.local,
      ),
      <String, Object?>{'kind': 'typed_data', 'length': 6},
    );
    expect(
      sanitizer.sanitize(
        bytes.buffer,
        destination: ObservabilityDestinationKind.local,
      ),
      <String, Object?>{'kind': 'byte_buffer', 'length': 6},
    );
    expect(
      sanitizer.sanitize(
        stream.stream,
        destination: ObservabilityDestinationKind.local,
      ),
      <String, Object?>{'kind': 'binary_stream', 'length': null},
    );
    expect(stream.hasListener, isFalse);
  });
}

ObservabilitySanitizer _diagnosticSanitizer() => ObservabilitySanitizer(
  policy: ObservabilityPrivacyPolicy.fromProfile(
    profile: ObservabilityPrivacyProfile.diagnostic,
  ),
);

final class _ExplosiveError {
  int toStringCalls = 0;

  @override
  String toString() {
    toStringCalls += 1;
    throw StateError('private error');
  }
}

final class _ExplosiveKey {
  int toStringCalls = 0;

  @override
  String toString() {
    toStringCalls += 1;
    throw StateError('private key');
  }
}

final class _ExplosiveValue {
  int toStringCalls = 0;

  @override
  String toString() {
    toStringCalls += 1;
    throw StateError('private value');
  }
}

final class _ExplosiveStackTrace implements StackTrace {
  @override
  String toString() => throw StateError('private stack');
}

final class _SafeId {
  const _SafeId(this.value);

  final int value;
}

final class _SafeIdProjector implements ObservabilityValueProjector {
  @override
  bool supports(Object value) => value is _SafeId;

  @override
  ObservabilityClassifiedValue<Object?> project(Object value) =>
      ObservabilityClassifiedValue<Object?>(
        (value as _SafeId).value,
        classes: <ObservabilityDataClass>{ObservabilityDataClass.userId},
      );
}

final class _PartialThrowClassifier implements ObservabilityDataClassifier {
  @override
  Iterable<ObservabilityDataClass> classify(
    Object? value, {
    String? key,
    ObservabilityDataClass? container,
  }) sync* {
    yield ObservabilityDataClass.safeMetadata;
    throw StateError('classifier failed after a partial result');
  }
}

final class _ManyClassesClassifier implements ObservabilityDataClassifier {
  @override
  Iterable<ObservabilityDataClass> classify(
    Object? value, {
    String? key,
    ObservabilityDataClass? container,
  }) sync* {
    yield ObservabilityDataClass.safeMetadata;
    yield ObservabilityDataClass.safeStatus;
  }
}
