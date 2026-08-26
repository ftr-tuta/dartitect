import 'dart:convert';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('10k versioned projection bounds remaps and releases nodes', () async {
    await _warmUp();

    var entities = List<({int id, int version})>.generate(
      10000,
      (id) => (id: id, version: 1),
      growable: false,
    );
    final incremental = LiveCollection<int, int>();
    final replaceAll = LiveCollection<int, int>();
    _update(incremental, entities, CollectionUpdatePolicy.versionedByKey);
    _update(replaceAll, entities, CollectionUpdatePolicy.replaceAll);

    entities = List<({int id, int version})>.of(entities);
    entities[5000] = (id: 5000, version: 2);
    final oneStopwatch = Stopwatch()..start();
    _update(incremental, entities, CollectionUpdatePolicy.versionedByKey);
    oneStopwatch.stop();
    final oneProjectionCount = incremental.lastProjectionCount;
    _update(replaceAll, entities, CollectionUpdatePolicy.replaceAll);
    final replaceProjectionCount = replaceAll.lastProjectionCount;

    entities = List<({int id, int version})>.of(entities);
    for (var id = 0; id < 100; id += 1) {
      entities[id] = (id: id, version: 2);
    }
    final hundredStopwatch = Stopwatch()..start();
    _update(incremental, entities, CollectionUpdatePolicy.versionedByKey);
    hundredStopwatch.stop();
    final hundredProjectionCount = incremental.lastProjectionCount;
    final nodesBeforeDispose = incremental.nodeCount;
    final reduction = 1 - (hundredProjectionCount / replaceProjectionCount);

    await incremental.dispose();
    await replaceAll.dispose();
    // ignore: avoid_print
    print(
      jsonEncode(<String, Object>{
        'items': 10000,
        'oneChangeProjections': oneProjectionCount,
        'oneChangeMicroseconds': oneStopwatch.elapsedMicroseconds,
        'hundredChangeProjections': hundredProjectionCount,
        'hundredChangeMicroseconds': hundredStopwatch.elapsedMicroseconds,
        'replaceAllProjections': replaceProjectionCount,
        'remapReduction': reduction,
        'nodesBeforeDispose': nodesBeforeDispose,
        'nodesAfterDispose': incremental.nodeCount,
        'timersAfterDispose': incremental.activeTimerCount,
      }),
    );

    expect(oneProjectionCount, 1);
    expect(hundredProjectionCount, 100);
    expect(replaceProjectionCount, 10000);
    expect(reduction, greaterThanOrEqualTo(0.9));
    expect(nodesBeforeDispose, 10000);
    expect(incremental.nodeCount, 0);
    expect(incremental.activeTimerCount, 0);
  });

  test('10k background projection matches inline and drains isolate', () async {
    final entities = List<({int id, int version})>.generate(
      10000,
      (id) => (id: id, version: id % 17),
      growable: false,
    );
    final inline = LiveCollection<int, int>();
    final background = LiveCollection<int, int>();
    final executor =
        IsolateProjectionExecutor<
          List<CollectionProjectionInput<int, ({int id, int version})>>,
          List<CollectionProjectionOutput<int, int>>
        >(project: _projectInBackground);

    final inlineWatch = Stopwatch()..start();
    inline.update<({int id, int version})>(
      entities,
      keyOf: _recordKey,
      versionOf: _recordVersion,
      project: _recordProjection,
      policy: CollectionUpdatePolicy.versionedByKey,
    );
    inlineWatch.stop();

    final backgroundWatch = Stopwatch()..start();
    await background.updateProjected<({int id, int version})>(
      entities,
      keyOf: _recordKey,
      versionOf: _recordVersion,
      project: _failInlineProjection,
      policy: CollectionUpdatePolicy.versionedByKey,
      execution: ProjectionExecution.background,
      executor: executor,
    );
    backgroundWatch.stop();

    int checksum(LiveCollection<int, int> collection) => collection.keys.value
        .fold(0, (sum, key) => sum + key + (collection.item(key).value ?? 0));
    final inlineChecksum = checksum(inline);
    final backgroundChecksum = checksum(background);
    final nodesBeforeDispose = background.nodeCount;
    await inline.dispose();
    await background.dispose();
    await executor.disposeAsync();

    // ignore: avoid_print
    print(
      jsonEncode(<String, Object>{
        'items': 10000,
        'inlineMicroseconds': inlineWatch.elapsedMicroseconds,
        'backgroundMicroseconds': backgroundWatch.elapsedMicroseconds,
        'inlineChecksum': inlineChecksum,
        'backgroundChecksum': backgroundChecksum,
        'parity': inlineChecksum == backgroundChecksum,
        'nodesBeforeDispose': nodesBeforeDispose,
        'nodesAfterDispose': background.nodeCount,
        'activeIsolatesAfterDispose': executor.activeTaskCount,
      }),
    );

    expect(backgroundChecksum, inlineChecksum);
    expect(nodesBeforeDispose, 10000);
    expect(background.nodeCount, 0);
    expect(executor.activeTaskCount, 0);
  });
}

int _recordKey(({int id, int version}) entity) => entity.id;

int _recordVersion(({int id, int version}) entity) => entity.version;

int _recordProjection(({int id, int version}) entity) => entity.version * 2;

int _failInlineProjection(({int id, int version}) entity) =>
    throw StateError('background benchmark projected inline');

List<CollectionProjectionOutput<int, int>> _projectInBackground(
  List<CollectionProjectionInput<int, ({int id, int version})>> inputs,
) => inputs
    .map(
      (input) => CollectionProjectionOutput<int, int>(
        key: input.key,
        value: _recordProjection(input.source),
      ),
    )
    .toList(growable: false);

void _update(
  LiveCollection<int, int> collection,
  List<({int id, int version})> entities,
  CollectionUpdatePolicy policy,
) {
  collection.update<({int id, int version})>(
    entities,
    keyOf: (entity) => entity.id,
    versionOf: (entity) => entity.version,
    project: (entity) => entity.version,
    policy: policy,
  );
}

Future<void> _warmUp() async {
  final collection = LiveCollection<int, int>();
  var entities = List<({int id, int version})>.generate(
    1000,
    (id) => (id: id, version: 1),
    growable: false,
  );
  _update(collection, entities, CollectionUpdatePolicy.versionedByKey);
  entities = List<({int id, int version})>.of(entities);
  entities[0] = (id: 0, version: 2);
  _update(collection, entities, CollectionUpdatePolicy.versionedByKey);
  await collection.dispose();
}
