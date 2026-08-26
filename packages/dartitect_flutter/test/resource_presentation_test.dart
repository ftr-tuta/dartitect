import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final snapshot = ResourceSnapshot<List<int>, String>(
    value: const <int>[1],
    metadata: 'cached',
    revision: 3,
    observedAt: DateTime.utc(2026, 8, 24),
    isStale: false,
  );

  test('projects waiting, content, empty, and expected failure', () {
    expect(
      const ResourceWaiting<ResourceSnapshot<List<int>, String>, String>()
          .toPresentation(isEmpty: (value) => value.isEmpty),
      isA<ResourcePresentationWaiting<List<int>, String, String>>(),
    );
    expect(
      ResourceReady<ResourceSnapshot<List<int>, String>, String>(snapshot)
          .toPresentation(isEmpty: (value) => value.isEmpty),
      isA<ResourcePresentationContent<List<int>, String, String>>(),
    );
    final empty = ResourceSnapshot<List<int>, String>(
      value: const <int>[],
      metadata: 'cached',
      revision: 4,
      observedAt: DateTime.utc(2026, 8, 24),
      isStale: false,
    );
    expect(
      ResourceReady<ResourceSnapshot<List<int>, String>, String>(empty)
          .toPresentation(isEmpty: (value) => value.isEmpty),
      isA<ResourcePresentationEmpty<List<int>, String, String>>(),
    );
    final failed = ResourceFailed<ResourceSnapshot<List<int>, String>, String>(
      'offline',
      lastData: snapshot,
      hasData: true,
    ).toPresentation(isEmpty: (value) => value.isEmpty);
    expect(
      failed,
      isA<ResourcePresentationFailure<List<int>, String, String>>(),
    );
    expect(failed.snapshot, same(snapshot));
  });

  test('crash stays distinct from an expected failure', () {
    final stack = StackTrace.current;
    final projected =
        ResourceCrashed<ResourceSnapshot<List<int>, String>, String>(
          StateError('crash'),
          stack,
          lastData: snapshot,
          hasData: true,
        ).toPresentation(isEmpty: (value) => value.isEmpty);

    expect(
      (projected as ResourcePresentationFailure<List<int>, String, String>)
          .cause,
      isA<ResourcePresentationCrash<String>>(),
    );
  });
}
