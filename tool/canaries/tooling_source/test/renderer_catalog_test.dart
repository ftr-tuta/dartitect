import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test('executes every scaffold renderer family', () {
    const factory = ScaffoldFactory(
      packageName: 'dartitect_tooling_packaged_canary',
    );
    final operations = <FileGenerationOperation>[
      ...factory.init(config: DartitectConfig()),
      ...factory.agents(),
      ...factory.viewModel('standalone'),
      ...factory.service('service'),
      for (final profile in FeatureProfile.values)
        ...factory.profile(
          FeatureScaffoldOptions(
            profile: profile,
            scope: FeatureScope.application,
            storageContext: switch (profile) {
              FeatureProfile.local || FeatureProfile.online => null,
              _ => 'primary',
            },
            transport: profile == FeatureProfile.local ? null : 'api',
            pagination: profile == FeatureProfile.offlineFull
                ? FeaturePagination.cursor
                : FeaturePagination.none,
            headlessTargets: profile == FeatureProfile.offlineFull
                ? const <DartitectPlatform>{DartitectPlatform.android}
                : const <DartitectPlatform>{},
          ),
          'catalog',
        ),
    ];
    expect(
      operations.map((operation) => operation.rendererId).toSet(),
      containsAll(<String>{
        'scaffold.agents',
        'scaffold.config',
        'scaffold.cursor-page',
        'scaffold.feature-factory',
        'scaffold.feature-model',
        'scaffold.headless-sync',
        'scaffold.local-store',
        'scaffold.mapper',
        'scaffold.mapping-test',
        'scaffold.memory-repository',
        'scaffold.mutation',
        'scaffold.remote-dto',
        'scaffold.remote-port',
        'scaffold.repository-contract',
        'scaffold.repository-contract-test',
        'scaffold.service',
        'scaffold.standalone-view-model',
        'scaffold.standalone-view-model-test',
        'scaffold.sync-dataset',
        'scaffold.view',
        'scaffold.view-model',
        'scaffold.view-model-test',
        'scaffold.view-test',
      }),
    );
  });

  test('executes blueprint and unmanaged-output renderer families', () async {
    final root = await Directory.systemTemp.createTemp(
      'dartitect-tooling-renderers-',
    );
    addTearDown(() => root.delete(recursive: true));
    final blueprint = Directory('${root.path}/blueprints/strict');
    await Directory('${blueprint.path}/templates').create(recursive: true);
    const content = 'renderer canary\n';
    await File('${blueprint.path}/templates/contract.txt')
        .writeAsString(content);
    await File('${blueprint.path}/blueprint.json').writeAsString(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'id': 'renderer-canary',
        'version': 1,
        'templates': <Object?>[
          <String, Object?>{
            'source': 'templates/contract.txt',
            'path': 'docs/architecture/contract.txt',
            'sha256': sha256.convert(utf8.encode(content)).toString(),
          },
        ],
      }),
    );
    final report = await DartitectBlueprintService(root)
        .inspect('blueprints/strict');
    expect(
      report.operations.map((operation) => operation.rendererId),
      containsAll(<String>[
        'blueprint.renderer-canary.template',
        'blueprint.renderer-canary.digest-lock',
      ]),
    );

    final orphan = File('${root.path}/lib/orphan.wiring.dartitect.g.dart');
    await orphan.parent.create(recursive: true);
    await orphan.writeAsString('// orphan\n');
    final plan = await GenerationEngine(
      root,
      namespace: const GenerationNamespace(
        'renderer-canary',
        fullyGeneratedSuffix: '.wiring.dartitect.g.dart',
      ),
    ).plan(const <FileGenerationOperation>[], manageFullyGenerated: true);
    expect(
      plan.operations.single.operation.rendererId,
      'generation.unmanaged-output',
    );
  });
}
