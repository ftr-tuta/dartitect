import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('10k versioned projection touches only changed item nodes', () async {
    final timers = _FakeTimerFactory();
    final collection = LiveCollection<int, String>(
      tombstoneRetention: const Duration(minutes: 5),
      timerFactory: timers,
    );
    var entities = List<_Entity>.generate(
      10000,
      (index) => _Entity(index, 1, 'item:$index'),
      growable: false,
    );
    var projectCalls = 0;
    void update(List<_Entity> values) {
      collection.update<_Entity>(
        values,
        keyOf: (entity) => entity.id,
        project: (entity) {
          projectCalls += 1;
          return entity.label;
        },
        versionOf: (entity) => entity.version,
        policy: CollectionUpdatePolicy.versionedByKey,
      );
    }

    update(entities);
    expect(projectCalls, 10000);
    expect(collection.nodeCount, 10000);
    expect(collection.keys.value.length, 10000);
    expect(collection.length.value, 10000);

    var keyNotifications = 0;
    var lengthNotifications = 0;
    var itemNotifications = 0;
    void keysChanged() => keyNotifications += 1;
    void lengthChanged() => lengthNotifications += 1;
    final changedItem = collection.item(5000);
    void itemChanged() => itemNotifications += 1;
    collection.keys.addListener(keysChanged);
    collection.length.addListener(lengthChanged);
    changedItem.addListener(itemChanged);
    final changes = <CollectionChange<int>>[];
    final subscription = collection.changes.listen(changes.add);

    entities = List<_Entity>.of(entities);
    entities[5000] = const _Entity(5000, 2, 'changed');
    projectCalls = 0;
    update(entities);
    expect(projectCalls, 1);
    expect(collection.lastProjectionCount, 1);
    expect(changedItem.value, 'changed');
    expect(itemNotifications, 1);
    expect(keyNotifications, 0);
    expect(lengthNotifications, 0);
    expect(changes, hasLength(1));
    expect(changes.single.kind, CollectionChangeKind.updated);
    changes.clear();

    entities = List<_Entity>.of(entities);
    for (var index = 0; index < 100; index += 1) {
      entities[index] = _Entity(index, 2, 'batch:$index');
    }
    projectCalls = 0;
    update(entities);
    expect(projectCalls, 100);
    expect(collection.lastProjectionCount, 100);
    expect(itemNotifications, 1);
    expect(keyNotifications, 0);
    expect(lengthNotifications, 0);
    expect(
      changes.where((change) => change.kind == CollectionChangeKind.updated),
      hasLength(100),
    );
    changes.clear();

    final replaceAll = LiveCollection<int, String>();
    var replaceCalls = 0;
    replaceAll.update<_Entity>(
      entities,
      keyOf: (entity) => entity.id,
      project: (entity) {
        replaceCalls += 1;
        return entity.label;
      },
      policy: CollectionUpdatePolicy.replaceAll,
    );
    replaceCalls = 0;
    replaceAll.update<_Entity>(
      entities,
      keyOf: (entity) => entity.id,
      project: (entity) {
        replaceCalls += 1;
        return entity.label;
      },
      policy: CollectionUpdatePolicy.replaceAll,
    );
    expect(replaceCalls, 10000);
    expect(
      collection.lastProjectionCount * 10,
      lessThanOrEqualTo(replaceCalls),
    );
    await replaceAll.dispose();

    entities = entities.reversed.toList(growable: false);
    projectCalls = 0;
    update(entities);
    expect(projectCalls, 0);
    expect(keyNotifications, 1);
    expect(lengthNotifications, 0);
    expect(itemNotifications, 1);
    expect(
      changes.where((change) => change.kind == CollectionChangeKind.moved),
      hasLength(10000),
    );
    changes.clear();

    entities = entities.where((entity) => entity.id != 5000).toList();
    update(entities);
    expect(changedItem.isPresent, isFalse);
    expect(changedItem.value, isNull);
    expect(itemNotifications, 2);
    expect(keyNotifications, 2);
    expect(lengthNotifications, 1);
    expect(collection.tombstoneCount, 1);
    expect(
      collection.activeTimerCount,
      0,
      reason: 'listener retains tombstone',
    );

    changedItem.removeListener(itemChanged);
    expect(collection.activeTimerCount, 1);
    timers.advance(const Duration(minutes: 5));
    expect(changedItem.isAttached, isFalse);
    expect(collection.tombstoneCount, 0);
    expect(collection.nodeCount, 9999);

    entities = <_Entity>[...entities, const _Entity(10000, 1, 'new')];
    update(entities);
    expect(collection.length.value, 10000);
    expect(keyNotifications, 3);
    expect(lengthNotifications, 2);
    expect(collection.nodeCount, 10000);

    collection.keys.removeListener(keysChanged);
    collection.length.removeListener(lengthChanged);
    await subscription.cancel();
    await collection.dispose();
    expect(collection.nodeCount, 0);
    expect(collection.activeTimerCount, 0);
  });

  test(
    'duplicate key and projection crash preserve the stable snapshot',
    () async {
      final collection = LiveCollection<int, String>();
      collection.update<_Entity>(
        const <_Entity>[_Entity(1, 1, 'one'), _Entity(2, 1, 'two')],
        keyOf: (entity) => entity.id,
        project: (entity) => entity.label,
        versionOf: (entity) => entity.version,
        policy: CollectionUpdatePolicy.versionedByKey,
      );
      final revision = collection.revision;
      final projectionCount = collection.projectionCount;
      var attemptedProjections = 0;

      expect(
        () => collection.update<_Entity>(
          const <_Entity>[_Entity(1, 2, 'changed'), _Entity(1, 3, 'duplicate')],
          keyOf: (entity) => entity.id,
          project: (entity) {
            attemptedProjections += 1;
            return entity.label;
          },
          versionOf: (entity) => entity.version,
          policy: CollectionUpdatePolicy.versionedByKey,
        ),
        throwsA(isA<DuplicateCollectionKeyException<int>>()),
      );
      expect(attemptedProjections, 0);
      expect(collection.revision, revision);
      expect(collection.projectionCount, projectionCount);
      expect(collection.keys.value, <int>[1, 2]);
      expect(collection.item(1).value, 'one');

      expect(
        () => collection.update<_Entity>(
          const <_Entity>[_Entity(1, 2, 'changed'), _Entity(2, 1, 'two')],
          keyOf: (entity) => entity.id,
          project: (entity) => throw StateError('projection failed'),
          versionOf: (entity) => entity.version,
          policy: CollectionUpdatePolicy.versionedByKey,
        ),
        throwsStateError,
      );
      expect(collection.revision, revision);
      expect(collection.projectionCount, projectionCount);
      expect(collection.item(1).value, 'one');
      await collection.dispose();
    },
  );

  test('diffByKey reuses equal sources while replaceAll never does', () async {
    final diff = LiveCollection<int, String>();
    var calls = 0;
    void update(List<(int, String)> values) {
      diff.update<(int, String)>(
        values,
        keyOf: (value) => value.$1,
        project: (value) {
          calls += 1;
          return value.$2;
        },
        policy: CollectionUpdatePolicy.diffByKey,
      );
    }

    update(const <(int, String)>[(1, 'one'), (2, 'two')]);
    calls = 0;
    update(const <(int, String)>[(1, 'one'), (2, 'two')]);
    expect(calls, 0);
    update(const <(int, String)>[(1, 'changed'), (2, 'two')]);
    expect(calls, 1);
    expect(diff.item(1).value, 'changed');
    await diff.dispose();
  });

  test(
    'inline remains default and background projection has exact parity',
    () async {
      final inline = LiveCollection<int, String>();
      final background = LiveCollection<int, String>();
      final executor =
          IsolateProjectionExecutor<
            List<CollectionProjectionInput<int, _Entity>>,
            List<CollectionProjectionOutput<int, String>>
          >(project: _projectEntities);
      final initial = const <_Entity>[
        _Entity(1, 1, 'one'),
        _Entity(2, 1, 'two'),
      ];
      var inlineCalls = 0;

      expect(
        await inline.updateProjected<_Entity>(
          initial,
          keyOf: _entityKey,
          project: (entity) {
            inlineCalls += 1;
            return entity.label.toUpperCase();
          },
          versionOf: _entityVersion,
          policy: CollectionUpdatePolicy.versionedByKey,
        ),
        isTrue,
      );
      expect(inlineCalls, 2, reason: 'inline must remain the default');
      await background.updateProjected<_Entity>(
        initial,
        keyOf: _entityKey,
        project: _mustNotProjectInline,
        versionOf: _entityVersion,
        policy: CollectionUpdatePolicy.versionedByKey,
        execution: ProjectionExecution.background,
        executor: executor,
      );

      final changed = const <_Entity>[
        _Entity(1, 1, 'one'),
        _Entity(2, 2, 'changed'),
      ];
      inline.update<_Entity>(
        changed,
        keyOf: _entityKey,
        project: (entity) => entity.label.toUpperCase(),
        versionOf: _entityVersion,
        policy: CollectionUpdatePolicy.versionedByKey,
      );
      await background.updateProjected<_Entity>(
        changed,
        keyOf: _entityKey,
        project: _mustNotProjectInline,
        versionOf: _entityVersion,
        policy: CollectionUpdatePolicy.versionedByKey,
        execution: ProjectionExecution.background,
        executor: executor,
      );

      String snapshot(LiveCollection<int, String> value) => value.keys.value
          .map((key) => '$key:${value.item(key).value}')
          .join('|');
      expect(snapshot(background), snapshot(inline));
      expect(background.lastProjectionCount, 1);
      expect(background.revision, inline.revision);
      expect(executor.activeTaskCount, 0);

      final noWorkExecutor =
          IsolateProjectionExecutor<
            List<CollectionProjectionInput<int, _Entity>>,
            List<CollectionProjectionOutput<int, String>>
          >(project: _crashEntityProjection);
      await background.updateProjected<_Entity>(
        changed,
        keyOf: _entityKey,
        project: _mustNotProjectInline,
        versionOf: _entityVersion,
        policy: CollectionUpdatePolicy.versionedByKey,
        execution: ProjectionExecution.background,
        executor: noWorkExecutor,
      );
      expect(background.lastProjectionCount, 0);
      expect(noWorkExecutor.activeTaskCount, 0);
      await noWorkExecutor.disposeAsync();

      await inline.dispose();
      await background.dispose();
      await executor.disposeAsync();
    },
  );

  test(
    'crash cancellation and disposal never publish a stale result',
    () async {
      final collection = LiveCollection<int, String>();
      collection.update<_Entity>(
        const <_Entity>[_Entity(1, 1, 'stable')],
        keyOf: _entityKey,
        project: (entity) => entity.label,
        versionOf: _entityVersion,
        policy: CollectionUpdatePolicy.versionedByKey,
      );
      final revision = collection.revision;
      final crashing =
          IsolateProjectionExecutor<
            List<CollectionProjectionInput<int, _Entity>>,
            List<CollectionProjectionOutput<int, String>>
          >(project: _crashEntityProjection);

      await expectLater(
        collection.updateProjected<_Entity>(
          const <_Entity>[_Entity(1, 2, 'must-not-publish')],
          keyOf: _entityKey,
          project: _mustNotProjectInline,
          versionOf: _entityVersion,
          policy: CollectionUpdatePolicy.versionedByKey,
          execution: ProjectionExecution.background,
          executor: crashing,
        ),
        throwsA(isA<ProjectionRemoteException>()),
      );
      expect(collection.item(1).value, 'stable');
      expect(collection.revision, revision);
      expect(collection.projectionStatus, CollectionProjectionStatus.crashed);
      expect(collection.projectionError, isA<ProjectionRemoteException>());
      expect(
        '${collection.projectionStackTrace}',
        contains('_crashEntityProjection'),
      );
      await crashing.disposeAsync();

      final recovery =
          IsolateProjectionExecutor<
            List<CollectionProjectionInput<int, _Entity>>,
            List<CollectionProjectionOutput<int, String>>
          >(project: _projectEntities);
      await collection.updateProjected<_Entity>(
        const <_Entity>[_Entity(1, 2, 'recovered')],
        keyOf: _entityKey,
        project: _mustNotProjectInline,
        versionOf: _entityVersion,
        policy: CollectionUpdatePolicy.versionedByKey,
        execution: ProjectionExecution.background,
        executor: recovery,
      );
      expect(collection.item(1).value, 'RECOVERED');
      expect(collection.projectionStatus, CollectionProjectionStatus.idle);
      expect(collection.projectionError, isNull);
      await recovery.disposeAsync();

      final slow =
          IsolateProjectionExecutor<
            List<CollectionProjectionInput<int, _Entity>>,
            List<CollectionProjectionOutput<int, String>>
          >(project: _slowProjectEntities);
      final stale = collection.updateProjected<_Entity>(
        const <_Entity>[_Entity(1, 3, 'stale')],
        keyOf: _entityKey,
        project: _mustNotProjectInline,
        versionOf: _entityVersion,
        policy: CollectionUpdatePolicy.versionedByKey,
        execution: ProjectionExecution.background,
        executor: slow,
      );
      final staleExpectation = expectLater(
        stale,
        throwsA(isA<CancellationException>()),
      );
      collection.update<_Entity>(
        const <_Entity>[_Entity(1, 4, 'new-stable')],
        keyOf: _entityKey,
        project: (entity) => entity.label,
        versionOf: _entityVersion,
        policy: CollectionUpdatePolicy.versionedByKey,
      );
      await staleExpectation;
      expect(collection.item(1).value, 'new-stable');

      final disposed = collection.updateProjected<_Entity>(
        const <_Entity>[_Entity(1, 5, 'after-dispose')],
        keyOf: _entityKey,
        project: _mustNotProjectInline,
        versionOf: _entityVersion,
        policy: CollectionUpdatePolicy.versionedByKey,
        execution: ProjectionExecution.background,
        executor: slow,
      );
      final disposedExpectation = expectLater(
        disposed,
        throwsA(isA<CancellationException>()),
      );
      await collection.dispose();
      await disposedExpectation;
      await slow.disposeAsync();

      expect(collection.nodeCount, 0);
      expect(collection.projectionStatus, CollectionProjectionStatus.disposed);
      expect(slow.activeTaskCount, 0);
    },
  );
}

final class _Entity {
  const _Entity(this.id, this.version, this.label);

  final int id;
  final int version;
  final String label;
}

int _entityKey(_Entity entity) => entity.id;

int _entityVersion(_Entity entity) => entity.version;

String _mustNotProjectInline(_Entity entity) =>
    throw StateError('background projection ran inline');

List<CollectionProjectionOutput<int, String>> _projectEntities(
  List<CollectionProjectionInput<int, _Entity>> inputs,
) => inputs
    .map(
      (input) => CollectionProjectionOutput<int, String>(
        key: input.key,
        value: input.source.label.toUpperCase(),
      ),
    )
    .toList(growable: false);

List<CollectionProjectionOutput<int, String>> _crashEntityProjection(
  List<CollectionProjectionInput<int, _Entity>> inputs,
) => throw StateError('background collection projection crashed');

Future<List<CollectionProjectionOutput<int, String>>> _slowProjectEntities(
  List<CollectionProjectionInput<int, _Entity>> inputs,
) async {
  await Future<void>.delayed(const Duration(milliseconds: 30));
  return _projectEntities(inputs);
}

final class _FakeTimerFactory implements ReactiveTimerFactory {
  final List<_FakeTimer> _timers = <_FakeTimer>[];
  Duration _elapsed = Duration.zero;

  @override
  ReactiveTimerHandle schedule(Duration duration, void Function() callback) {
    final timer = _FakeTimer(_elapsed + duration, callback);
    _timers.add(timer);
    return timer;
  }

  void advance(Duration duration) {
    _elapsed += duration;
    final due = _timers
        .where((timer) => timer.isActive && timer.deadline <= _elapsed)
        .toList(growable: false);
    for (final timer in due) {
      timer.fire();
    }
  }
}

final class _FakeTimer implements ReactiveTimerHandle {
  _FakeTimer(this.deadline, this._callback);

  final Duration deadline;
  final void Function() _callback;
  var _active = true;

  @override
  bool get isActive => _active;

  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }
}
