import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/fixture_entity.dart';
import '../lib/objectbox.g.dart';

void main() {
  final originalWorkingDirectory = Directory.current;
  setUpAll(() {
    final fixture = Directory('tool/objectbox_native_fixture');
    if (fixture.existsSync()) Directory.current = fixture.absolute;
  });
  tearDownAll(() => Directory.current = originalWorkingDirectory);

  test('generated Store put/query cycle leaves no filesystem state', () async {
    const iterations = 500;
    final directory = await Directory.systemTemp.createTemp(
      'dartitect-objectbox-benchmark-',
    );
    final store = await openStore(directory: directory.path);
    final box = store.box<FixtureEntity>();
    final watch = Stopwatch()..start();
    for (var index = 0; index < iterations; index += 1) {
      box.put(FixtureEntity(value: 'value-$index'));
      final query = box
          .query(FixtureEntity_.value.equals('value-$index'))
          .build();
      try {
        expect(query.findIds(), hasLength(1));
      } finally {
        query.close();
      }
    }
    watch.stop();
    store.close();
    await directory.delete(recursive: true);
    expect(await directory.exists(), isFalse);
    // ignore: avoid_print
    print(
      jsonEncode(<String, double>{
        'objectbox_store_query_us_per_cycle':
            watch.elapsedMicroseconds / iterations,
      }),
    );
  });
}
