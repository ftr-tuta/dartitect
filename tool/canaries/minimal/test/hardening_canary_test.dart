import 'dart:async';
import 'dart:io';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('non-cooperative derived result cannot replace its successor', () async {
    final dependency = ValueNotifier<int>(0);
    final reads = <Completer<Result<int, String>>>[];
    final resource = DerivedAsyncResource<int, String>(
      dependencies: <Listenable>[dependency],
      policy: const ActivationPolicy.alwaysHot(),
      load: (_) {
        final read = Completer<Result<int, String>>();
        reads.add(read);
        return read.future;
      },
    );
    addTearDown(() async {
      await resource.dispose();
      dependency.dispose();
    });
    await resource.start();
    await _waitFor(() => reads.length == 1);

    dependency.value = 1;
    reads[0].complete(const Ok<int>(10));
    await _waitFor(() => reads.length == 2);
    expect(resource.state.lastData, isNot(10));
    reads[1].complete(const Ok<int>(20));
    await _waitFor(() => resource.state.lastData == 20);

    expect(resource.state.lastData, 20);
    expect(resource.dependencyRevision, 1);
  });

  test(
    'large assets and a multipackage workspace remain bounded inputs',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'dartitect-packaged-hardening-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      await File('${root.path}/pubspec.yaml').writeAsString('''name: fleet_root
workspace:
  - packages/*
''');
      final app = Directory('${root.path}/packages/app');
      final shared = Directory('${root.path}/packages/shared');
      await app.create(recursive: true);
      await shared.create(recursive: true);
      await File('${app.path}/pubspec.yaml').writeAsString('name: fleet_app\n');
      await File('${shared.path}/pubspec.yaml')
          .writeAsString('name: fleet_shared\n');
      final main = File('${app.path}/lib/main.dart');
      await main.parent.create(recursive: true);
      await main.writeAsString('void main() {}\n');
      final asset = File('${app.path}/assets/catalog.bin');
      await asset.parent.create(recursive: true);
      await asset.writeAsBytes(List<int>.filled(8 * 1024 * 1024, 7));

      final first = await DartitectProjectService(root).inspectProject();
      final second = await DartitectProjectService(root).inspectProject();
      final fleet = await DartitectFleetService(root)
          .versions(<String>['packages/shared', 'packages/app']);

      expect(first.project['dartFiles'], 1);
      expect(second.toJson(), first.toJson());
      expect(fleet.projects.map((project) => project['root']), <String>[
        'packages/app',
        'packages/shared',
      ]);
      expect(fleet.toJson().toString(), isNot(contains(root.path)));
    },
  );
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  throw StateError('Packaged hardening canary did not settle.');
}
