import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'codec migrates one version at a time and rejects invalid envelopes',
    () {
      final codec = _codec();

      expect(
        codec.decode(<String, Object?>{'version': 1, 'payload': 3}),
        const Ok<_UiState>(_UiState(3)),
      );
      expect(
        codec.decode(<String, Object?>{'version': 3, 'payload': 3}),
        isA<Err<_RestoreFailure>>().having(
          (result) => result.failure.issue,
          'issue',
          VersionedRestorationIssue.unsupportedVersion,
        ),
      );
      expect(
        codec.decode(<String, Object?>{'version': 2, 'payload': 3, 'extra': 1}),
        isA<Err<_RestoreFailure>>().having(
          (result) => result.failure.issue,
          'issue',
          VersionedRestorationIssue.invalidEnvelope,
        ),
      );
    },
  );

  test('codec surfaces consumer payload failure and rejects unsafe output', () {
    final codec = _codec();
    expect(
      codec.decode(<String, Object?>{
        'version': 2,
        'payload': <String, Object?>{'count': 'invalid'},
      }),
      isA<Err<_RestoreFailure>>().having(
        (result) => result.failure.issue,
        'issue',
        VersionedRestorationIssue.nonRestorablePayload,
      ),
    );
    final unsafe = VersionedRestorationCodec<Object, _RestoreFailure>(
      currentVersion: 1,
      encodePayload: (_) => Object(),
      decodePayload: (payload) => Ok<Object>(payload!),
      mapIssue: _RestoreFailure.new,
    );
    expect(
      () => unsafe.encode(Object()),
      throwsA(isA<VersionedRestorationEncodingException>()),
    );
  });

  testWidgets('restorable property round-trips through Flutter buckets', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        restorationScopeId: 'app',
        home: _RestorationHost(key: _hostKey),
      ),
    );
    expect(find.text('count:0'), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    expect(find.text('count:1'), findsOneWidget);

    await tester.restartAndRestore();
    expect(_hostKey.currentState!.state.lastFailure?.issue, isNull);
    expect(tester.widget<Text>(find.textContaining('count:')).data, 'count:1');
  });

  test('history listenable borrows history and publishes local changes', () {
    final history = BoundedLocalHistory<int>(initialValue: 0);
    final listenable = LocalHistoryListenable<int>(history);
    var notifications = 0;
    listenable.addListener(() => notifications += 1);

    listenable
      ..edit(1)
      ..undo()
      ..redo();
    expect(listenable.value, 1);
    expect(notifications, 3);

    listenable.dispose();
    history.edit(2);
    expect(history.value, 2);
    history.dispose();
  });
}

final GlobalKey<_RestorationHostState> _hostKey =
    GlobalKey<_RestorationHostState>();

VersionedRestorationCodec<_UiState, _RestoreFailure> _codec() =>
    VersionedRestorationCodec<_UiState, _RestoreFailure>(
      currentVersion: 2,
      encodePayload: (value) => <String, Object?>{'count': value.count},
      decodePayload: (payload) {
        if (payload is Map<Object?, Object?> &&
            payload.length == 1 &&
            payload['count'] is int) {
          return Ok<_UiState>(_UiState(payload['count']! as int));
        }
        return Err<_RestoreFailure>(
          const _RestoreFailure(VersionedRestorationIssue.nonRestorablePayload),
          StackTrace.empty,
        );
      },
      migrations: <int, VersionedRestorationMigration<_RestoreFailure>>{
        1: (payload) => payload is int
            ? Ok<Object?>(<String, Object?>{'count': payload})
            : Err<_RestoreFailure>(
                const _RestoreFailure(
                  VersionedRestorationIssue.nonRestorablePayload,
                ),
                StackTrace.empty,
              ),
      },
      mapIssue: _RestoreFailure.new,
    );

final class _UiState {
  const _UiState(this.count);

  final int count;

  @override
  bool operator ==(Object other) => other is _UiState && count == other.count;

  @override
  int get hashCode => count;
}

final class _RestoreFailure {
  const _RestoreFailure(this.issue);

  final VersionedRestorationIssue issue;

  @override
  bool operator ==(Object other) =>
      other is _RestoreFailure && issue == other.issue;

  @override
  int get hashCode => issue.hashCode;
}

class _RestorationHost extends StatefulWidget {
  const _RestorationHost({super.key});

  @override
  State<_RestorationHost> createState() => _RestorationHostState();
}

class _RestorationHostState extends State<_RestorationHost>
    with RestorationMixin {
  final RestorableVersionedValue<_UiState, _RestoreFailure> state =
      RestorableVersionedValue<_UiState, _RestoreFailure>(
        initialValue: const _UiState(0),
        codec: _codec(),
      );

  @override
  String get restorationId => 'versioned-host';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(state, 'state');
  }

  @override
  void dispose() {
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Text('count:${state.value.count}'),
    floatingActionButton: FloatingActionButton(
      onPressed: () => setState(() {
        state.value = _UiState(state.value.count + 1);
      }),
    ),
  );
}
