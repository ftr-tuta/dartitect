import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test('feature scaffold renders a complete provider-neutral MVVM slice', () {
    const factory = ScaffoldFactory(packageName: 'sample_app');

    final withoutDomain = factory.feature('orders', includeDomain: false);
    final withDomain = factory.feature('orders', includeDomain: true);

    expect(withoutDomain, hasLength(8));
    expect(
      withoutDomain.map((operation) => operation.relativePath),
      containsAll(<String>[
        'lib/features/orders/application/orders_repository.dart',
        'lib/features/orders/infrastructure/memory_orders_repository.dart',
        'lib/features/orders/composition/orders_composition.dart',
        'lib/features/orders/presentation/orders_view_model.dart',
        'lib/features/orders/presentation/orders_view.dart',
        'test/features/orders/orders_view_model_test.dart',
        'test/features/orders/orders_repository_contract_test.dart',
        'test/features/orders/orders_view_test.dart',
      ]),
    );
    expect(
      withDomain.map((operation) => operation.relativePath),
      contains('lib/features/orders/domain/orders_repository.dart'),
    );
    final viewModel = withoutDomain
        .singleWhere(
          (operation) => operation.relativePath.endsWith('_view_model.dart'),
        )
        .content;
    expect(viewModel, contains('Command0<List<String>, OrdersFailure>'));
    expect(
      viewModel,
      contains(
        '// The async path calls ChangeNotifier.dispose after draining the command.\n'
        '  // ignore: must_call_super\n'
        '  void dispose() => unawaited(disposeAsync());',
      ),
    );
    expect(viewModel, isNot(contains('BuildContext')));
    final view = withoutDomain
        .singleWhere(
          (operation) => operation.relativePath.endsWith('_view.dart'),
        )
        .content;
    expect(view, contains('ViewModelHost<OrdersViewModel>.create'));
    expect(view, isNot(contains('infrastructure/')));
  });

  test('five stable blueprints render their required architectural seams', () {
    const factory = ScaffoldFactory(packageName: 'sample_app');

    final rendered = <ScaffoldBlueprint, List<FileGenerationOperation>>{
      for (final blueprint in ScaffoldBlueprint.values)
        blueprint: factory.blueprint(blueprint, 'catalog'),
    };

    expect(ScaffoldBlueprint.values.map((value) => value.cliName), <String>[
      'simple',
      'remote-read',
      'local-first',
      'offline-mutation',
      'sync-dataset',
    ]);
    for (final operations in rendered.values) {
      final paths = operations.map((operation) => operation.relativePath);
      expect(paths, contains(endsWith('catalog_model.dart')));
      expect(paths, contains(endsWith('catalog_view_model.dart')));
      expect(paths, contains(endsWith('catalog_composition.dart')));
      expect(paths, contains(endsWith('catalog_architecture_test.dart')));
      final viewModel = operations
          .singleWhere(
            (operation) =>
                operation.relativePath.endsWith('catalog_view_model.dart'),
          )
          .content;
      expect(viewModel, contains('// ignore: must_call_super'));
      expect(viewModel, contains('super.dispose();'));
      final model = operations
          .singleWhere(
            (operation) =>
                operation.relativePath.endsWith('catalog_model.dart'),
          )
          .content;
      expect(model, contains('final class CatalogModel({'));
      expect(model, contains('this : labels = immutableListCopy(labels);'));
    }
    expect(
      rendered[ScaffoldBlueprint.remoteRead]!.map(
        (operation) => operation.relativePath,
      ),
      containsAll(<String>[
        'lib/features/catalog/application/catalog_remote_port.dart',
        'lib/features/catalog/infrastructure/catalog_remote_dto.dart',
        'lib/features/catalog/infrastructure/catalog_mapper.dart',
      ]),
    );
    expect(
      rendered[ScaffoldBlueprint.localFirst]!
          .map((operation) => operation.content)
          .join(),
      contains('PullReactiveSource'),
    );
    expect(
      rendered[ScaffoldBlueprint.offlineMutation]!
          .map((operation) => operation.content)
          .join(),
      allOf(
        contains('MutationLane'),
        contains('MutationOutboxStore'),
        contains('final class const CatalogMutation({'),
      ),
    );
    expect(
      rendered[ScaffoldBlueprint.syncDataset]!
          .map((operation) => operation.content)
          .join(),
      allOf(contains('SyncDataset'), contains('SyncCheckpointStore')),
    );
  });

  test('public profiles preserve blueprint aliases and add bounded wiring', () {
    const factory = ScaffoldFactory(packageName: 'sample_app');
    expect(ScaffoldBlueprint.remoteRead.profileAlias, FeatureProfile.online);
    expect(ScaffoldBlueprint.localFirst.profileAlias, FeatureProfile.cache);
    expect(ScaffoldBlueprint.syncDataset.profileAlias, FeatureProfile.replica);
    expect(
      ScaffoldBlueprint.offlineMutation.profileAlias,
      FeatureProfile.offlineFull,
    );
    expect(ScaffoldBlueprint.simple.profileAlias, isNull);

    final operations = factory.profile(
      FeatureScaffoldOptions(
        profile: FeatureProfile.offlineFull,
        persistence: 'drift',
        transport: 'dio',
        cursorPagination: true,
        headlessSync: true,
        diagnostics: FeatureDiagnosticsLevel.full,
      ),
      'catalog',
    );
    final paths = operations.map((operation) => operation.relativePath);
    expect(paths.toSet(), hasLength(paths.length));
    expect(
      paths,
      containsAll(<String>[
        'lib/features/catalog/composition/catalog_feature_profile.dart',
        'lib/features/catalog/application/catalog_cursor_page.dart',
        'lib/features/catalog/composition/catalog_headless_sync.dart',
      ]),
    );
    expect(
      operations
          .singleWhere(
            (operation) =>
                operation.relativePath.endsWith('catalog_feature_profile.dart'),
          )
          .content,
      allOf(
        contains("profile = 'offline-full'"),
        contains("persistence = 'drift'"),
        contains("transport = 'dio'"),
      ),
    );
    expect(
      operations.every(
        (operation) => operation.ownership == GeneratedOwnership.generatedOnce,
      ),
      isTrue,
    );
  });
}
