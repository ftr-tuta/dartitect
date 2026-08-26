import 'dart:io';

import 'package:dartitect_objectbox/dartitect_objectbox.dart';

import 'fixture_entity.dart';
import 'objectbox.g.dart';

/// Opens and disposes a temporary Store using a consumer-generated model.
Future<void> main() async {
  final owner = await ObjectBoxStoreOwner.temporary(
    openStore: (directory) => openStore(directory: directory),
  );
  try {
    final box = owner.store.box<FixtureEntity>();
    final id = box.put(FixtureEntity(value: 'native-first'));
    stdout.writeln(box.get(id)?.value);
  } finally {
    await owner.disposeAsync();
  }
}
