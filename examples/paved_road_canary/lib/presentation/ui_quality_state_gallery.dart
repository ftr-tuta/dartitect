import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_flutter/dartitect_flutter_forms.dart';
import 'package:dartitect_flutter/dartitect_flutter_queries.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter/material.dart';

/// Synthetic exhaustive renderer proving every public presentation boundary.
final class CanaryStateGallery extends StatelessWidget {
  const CanaryStateGallery({
    required this.command,
    required this.form,
    required this.query,
    required this.resource,
    super.key,
  });

  final DartitectCommand<String, String> command;
  final DartitectFormController<String, String> form;
  final DartitectQueryController<String, String, String> query;
  final LiveResource<ResourceSnapshot<List<String>, int>, String> resource;

  @override
  Widget build(BuildContext context) => ListView(
    children: <Widget>[
      CommandStateBuilder<String, String>(
        command: command,
        idle: (context, state) => const Text('command idle'),
        running: (context, state) => const Text('command loading'),
        success: (context, state) => Text('command success ${state.value}'),
        failure: (context, state) =>
            Text('command expected failure ${state.failure}'),
        cancelled: (context, state) => const Text('command cancelled'),
        crashed: (context, state) =>
            Text('command crash ${state.error.runtimeType}'),
      ),
      DartitectFormSnapshotBuilder<String, String>(
        controller: form,
        builder: (context, snapshot, child) => Text('form ${snapshot.current}'),
      ),
      DartitectQueryStateBuilder<String, String, String>(
        controller: query,
        initial: (context, state) => const Text('query initial'),
        loading: (context, state) => Text(
          state.staleItems.isEmpty
              ? 'query loading'
              : 'query loading stale ${state.staleItems.join(',')}',
        ),
        empty: (context, state) => const Text('query empty'),
        content: (context, state) => Text(
          'query content ${state.items.join(',')}${state.stale ? ' stale' : ''}',
        ),
        failure: (context, state) => Text(
          'query expected failure ${state.failure}'
          '${state.staleItems.isEmpty ? '' : ' stale ${state.staleItems.join(',')}'}',
        ),
      ),
      ResourcePresentationBuilder<List<String>, String, int>(
        resource: resource,
        isEmpty: (value) => value.isEmpty,
        waiting: (context, state) => const Text('resource loading'),
        content: (context, state) =>
            Text('resource content ${state.snapshot.value.join(',')}'),
        empty: (context, state) => const Text('resource empty'),
        failure: (context, state, cause) => Text(
          'resource expected failure ${cause.failure}'
          '${state.snapshot == null ? '' : ' stale'}',
        ),
        crashed: (context, state, cause) =>
            Text('resource crash ${cause.error.runtimeType}'),
      ),
    ],
  );
}
