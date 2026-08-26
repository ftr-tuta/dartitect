import 'dart:async';

import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter/material.dart';

import 'catalog_model.dart';
import 'catalog_view_model.dart';

/// Consumer-owned Material rendering for the headless catalog workload.
final class CatalogPage extends StatefulWidget {
  /// Creates a page borrowing [viewModel].
  const CatalogPage({required this.viewModel, super.key});

  /// Runtime-owned catalog ViewModel.
  final CatalogViewModel viewModel;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

final class _CatalogPageState extends State<CatalogPage> {
  @override
  Widget build(BuildContext context) => EffectListener<CatalogEffect>(
    channel: widget.viewModel.effects,
    onEffect: (context, effect) {
      switch (effect) {
        case CatalogEffect.endOfList:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('The complete catalog is visible.')),
          );
      }
    },
    child: PagedLiveBuilder<CatalogCursor, int, CatalogItem, CatalogFailure>(
      resource: widget.viewModel.paged,
      builder: (context, resource, keys, child) => Column(
        children: <Widget>[
          TextField(
            decoration: const InputDecoration(labelText: 'Search catalog'),
            onSubmitted: (value) =>
                unawaited(widget.viewModel.searchCommand.execute(value)),
          ),
          if (resource.isBusy) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              itemCount: keys.length,
              itemBuilder: (context, index) {
                final key = keys[index];
                return ReactiveValueBuilder<CatalogItem?>(
                  key: ValueKey<int>(key),
                  value: resource.collection.item(key),
                  builder: (context, item, child) => item == null
                      ? const SizedBox.shrink()
                      : ListTile(title: Text(item.title)),
                );
              },
            ),
          ),
          if (resource.nextCursor != null)
            FilledButton(
              onPressed: resource.isLoadingMore
                  ? null
                  : () => unawaited(widget.viewModel.loadMoreCommand.execute()),
              child: const Text('Load more catalog'),
            ),
        ],
      ),
    ),
  );
}
