// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v2.
// ignore_for_file: prefer_initializing_formals, unnecessary_nullable_for_final_variable_declarations

import 'dart:async';

import 'package:dartitect/dartitect.dart';

/// Direct constructor inputs for the Tasks feature graph.
final class TasksFeatureModule<R, V> implements AsyncDisposable {
  TasksFeatureModule({
    required this.repository,
    required this.persistenceProvider,
    required this.transportProvider,
    required this.resource,
    required this.command,
    required this.pagination,
    required this.outbox,
    required this.syncDataset,
    required this.job,
    required this.diagnostics,
    required this.contractFixture,
    required this.createViewModel,
    required FutureOr<void> Function() dispose,
  }) : _dispose = dispose;

  final R repository;
  final Object? persistenceProvider;
  final Object transportProvider;
  final Object? resource;
  final Object? command;
  final Object? pagination;
  final Object? outbox;
  final Object? syncDataset;
  final Object? job;
  final Object? diagnostics;
  final Object contractFixture;
  final V Function(R repository) createViewModel;
  final FutureOr<void> Function() _dispose;
  var _disposed = false;

  V buildViewModel() {
    if (_disposed) throw StateError('Tasks feature module is disposed.');
    return createViewModel(repository);
  }

  @override
  Future<void> disposeAsync() async {
    if (_disposed) return;
    _disposed = true;
    await _dispose();
  }
}

/// Closed generated facts used by composition and capability reporting.
abstract final class TasksFeatureWiring {
  static const String profile = 'offline-full';
  static const String scope = 'application';
  static const String? storageContext = "primary";
  static const String? transport = "api";
  static const List<String> targets = <String>[];
  static const String pagination = 'cursor';
  static const String diagnostics = 'basic';
  static const String scheduler = 'workmanager';
  static const List<String> headlessTargets = <String>[
    'android',
    'ios',
    'macos',
    'linux',
    'web',
  ];
  static const List<String> capabilities = <String>[
    'attachments',
    'credentials',
    'forms',
    'queries',
  ];

  /// Creates the public application-host factory while keeping graph ownership
  /// and atomic publication inside generated code.
  static BootstrapCoordinator<V> Function() application<R, V>({
    required FutureOr<TasksFeatureModule<R, V>> Function() createModule,
  }) =>
      () => BootstrapCoordinator<V>(
        stages: const <BootstrapStage>[],
        buildRoot: (transaction, context) async {
          context.throwIfUnavailable();
          final module = transaction.own<TasksFeatureModule<R, V>>(
            await createModule(),
            (value) => value.disposeAsync(),
            label: 'tasks-feature-module',
          );
          context.throwIfUnavailable();
          return module.buildViewModel();
        },
      );
}
