import 'dart:convert';
import 'dart:io';

import '../config/dartitect_config.dart';
import 'generation_engine.dart';

/// Deterministic preview or apply receipt for managed feature wiring.
final class DartitectWiringReport {
  /// Creates a wiring report.
  const DartitectWiringReport({
    required this.plan,
    required this.applied,
    required this.writes,
  });

  /// Revalidated generation plan.
  final GenerationPlan plan;

  /// Whether the managed namespace was applied.
  final bool applied;

  /// Number of output writes or deletions performed.
  final int writes;

  /// Whether all managed outputs are current.
  bool get isFresh => applied || !plan.hasChanges && !plan.pendingRecovery;

  /// Stable machine-readable representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'command': 'wiring sync',
    'applied': applied,
    'fresh': isFresh,
    'pendingRecovery': plan.pendingRecovery,
    'writes': writes,
    'operations': <Object?>[
      for (final operation in plan.operations)
        <String, Object?>{
          'path': operation.operation.relativePath,
          'disposition': operation.disposition.name,
        },
    ],
  };
}

/// Converges direct-constructor feature wiring from strict config v2.
final class DartitectWiringService {
  /// Creates a service for one project root.
  DartitectWiringService(Directory root) : root = root.absolute;

  /// Project root whose managed namespace is synchronized.
  final Directory root;

  static const GenerationNamespace _namespace = GenerationNamespace(
    'wiring',
    fullyGeneratedSuffix: '.wiring.dartitect.g.dart',
  );

  /// Produces a read-only deterministic preview.
  Future<DartitectWiringReport> inspect({DartitectConfig? config}) async {
    final resolved = config ?? await _loadConfig();
    final plan = await GenerationEngine(
      root,
      namespace: _namespace,
    ).plan(_operations(resolved), manageFullyGenerated: true);
    return DartitectWiringReport(plan: plan, applied: false, writes: 0);
  }

  /// Recovers and atomically converges the complete managed namespace.
  Future<DartitectWiringReport> apply({DartitectConfig? config}) async {
    final resolved = config ?? await _loadConfig();
    final result = await GenerationEngine(
      root,
      namespace: _namespace,
    ).apply(_operations(resolved), manageFullyGenerated: true);
    return DartitectWiringReport(
      plan: result.plan,
      applied: true,
      writes:
          result.createdPaths.length +
          result.updatedPaths.length +
          result.deletedPaths.length,
    );
  }

  Future<DartitectConfig> _loadConfig() async {
    final file = File(_join(root.path, 'dartitect.json'));
    if (!await file.exists()) {
      throw const DartitectConfigException(
        '/features',
        'dartitect.json is required for wiring sync',
      );
    }
    return DartitectConfig.load(file);
  }

  static List<FileGenerationOperation> _operations(DartitectConfig config) {
    final entries = config.features.declarations.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return <FileGenerationOperation>[
      ..._applicationOperations(config),
      for (final entry in entries) ...<FileGenerationOperation>[
        FileGenerationOperation(
          relativePath:
              'lib/features/${entry.key}/composition/'
              '${entry.key}.wiring.dartitect.g.dart',
          content: _render(entry.key, entry.value, config.scheduler.provider),
          ownership: GeneratedOwnership.fullyGenerated,
          sourcePath: 'dartitect.json',
          rendererVersion: 2,
          semanticSchemaVersion: 1,
          inputSignature: jsonEncode(<String, Object?>{
            'name': entry.key,
            'scheduler': config.scheduler.toJson(),
            'declaration': entry.value.toJson(),
          }),
        ),
        if (entry.value.storageContext case final String storageName
            when config.storageContexts[storageName]?.provider == 'drift')
          _managedOperation(
            entry.key,
            entry.value,
            'infrastructure/${entry.key}_drift.wiring.dartitect.g.dart',
            _renderDrift(entry.key),
          ),
        if (entry.value.storageContext case final String storageName
            when config.storageContexts[storageName]?.provider == 'objectbox')
          _managedOperation(
            entry.key,
            entry.value,
            'infrastructure/${entry.key}_objectbox.wiring.dartitect.g.dart',
            _renderObjectBox(entry.key),
          ),
        if (entry.value.transport case final String transportName
            when config.transports[transportName]?.provider == 'dio')
          _managedOperation(
            entry.key,
            entry.value,
            'infrastructure/${entry.key}_dio.wiring.dartitect.g.dart',
            _renderDio(entry.key),
          ),
        if (config.scheduler.provider == 'workmanager' &&
            entry.value.headlessTargets.isNotEmpty)
          _managedOperation(
            entry.key,
            entry.value,
            'composition/${entry.key}_workmanager.wiring.dartitect.g.dart',
            _renderWorkmanager(entry.key),
          ),
      ],
    ];
  }

  static List<FileGenerationOperation> _applicationOperations(
    DartitectConfig config,
  ) {
    final observabilityProvider = config.observability.provider;
    final signature = jsonEncode(<String, Object?>{
      'scheduler': config.scheduler.toJson(),
      'observability': observabilityProvider,
    });
    return <FileGenerationOperation>[
      FileGenerationOperation(
        relativePath:
            'lib/composition/application_module.wiring.dartitect.g.dart',
        content: _renderApplicationModule(
          scheduler: config.scheduler.provider,
          observability: observabilityProvider,
        ),
        ownership: GeneratedOwnership.fullyGenerated,
        sourcePath: 'dartitect.json',
        rendererVersion: 1,
        semanticSchemaVersion: 1,
        inputSignature: signature,
      ),
      FileGenerationOperation(
        relativePath: 'lib/composition/session_module.wiring.dartitect.g.dart',
        content: _renderSessionModule(),
        ownership: GeneratedOwnership.fullyGenerated,
        sourcePath: 'dartitect.json',
        rendererVersion: 1,
        semanticSchemaVersion: 1,
        inputSignature: signature,
      ),
    ];
  }

  static FileGenerationOperation _managedOperation(
    String name,
    DartitectFeatureDeclaration declaration,
    String suffix,
    String content,
  ) => FileGenerationOperation(
    relativePath: 'lib/features/$name/$suffix',
    content: content,
    ownership: GeneratedOwnership.fullyGenerated,
    sourcePath: 'dartitect.json',
    rendererVersion: 2,
    semanticSchemaVersion: 1,
    inputSignature: jsonEncode(<String, Object?>{
      'name': name,
      'declaration': declaration.toJson(),
      'output': suffix,
    }),
  );

  static String _render(
    String name,
    DartitectFeatureDeclaration declaration,
    String scheduler,
  ) {
    final type = _pascal(name);
    final headless = _renderStringList(
      declaration.headlessTargets.map((target) => target.wireName),
    );
    final targets = _renderStringList(
      declaration.targets.map((target) => target.wireName),
    );
    final capabilities = _renderStringList(
      declaration.capabilities.map((capability) => capability.wireName),
    );
    return '''// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v2.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:dartitect/dartitect.dart';

/// Direct constructor inputs for the $type feature graph.
final class ${type}FeatureModule<R, V> implements AsyncDisposable {
  ${type}FeatureModule({
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
    if (_disposed) throw StateError('$type feature module is disposed.');
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
abstract final class ${type}FeatureWiring {
  static const String profile = '${declaration.profile.wireName}';
  static const String scope = '${declaration.scope.wireName}';
  static const String? storageContext = ${jsonEncode(declaration.storageContext)};
  static const String? transport = ${jsonEncode(declaration.transport)};
  static const List<String> targets = $targets;
  static const String pagination = '${declaration.pagination.wireName}';
  static const String diagnostics = '${declaration.diagnostics.wireName}';
  static const String scheduler = '$scheduler';
  static const List<String> headlessTargets = $headless;
  static const List<String> capabilities = $capabilities;

  /// Creates the public application-host factory while keeping graph ownership
  /// and atomic publication inside generated code.
  static BootstrapCoordinator<V> Function() application<R, V>({
    required FutureOr<${type}FeatureModule<R, V>> Function() createModule,
  }) =>
      () => BootstrapCoordinator<V>(
        stages: const <BootstrapStage>[],
        buildRoot: (transaction, context) async {
          context.throwIfUnavailable();
          final module = transaction.own<${type}FeatureModule<R, V>>(
            await createModule(),
            (value) => value.disposeAsync(),
            label: '$name-feature-module',
          );
          context.throwIfUnavailable();
          return module.buildViewModel();
        },
      );
}
''';
  }

  static String _renderApplicationModule({
    required String scheduler,
    required String observability,
  }) =>
      '''// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v2.

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';

/// Directly constructed application graph; it is not a service locator.
final class ApplicationGraph {
  const ApplicationGraph({
    required this.sessions,
    required this.scheduler,
    required this.observability,
  });

  final SessionRuntimeController<Object, Object> sessions;
  final String scheduler;
  final String observability;
}

/// Tooling-materialized application composition module.
abstract final class ApplicationModule {
  static BootstrapCoordinator<ApplicationGraph> create() =>
      BootstrapCoordinator<ApplicationGraph>(
        stages: const <BootstrapStage>[],
        buildRoot: (transaction, _) {
          final sessions = transaction.own(
            SessionRuntimeController<Object, Object>(),
            (controller) => controller.disposeAsync(),
          );
          return ApplicationGraph(
            sessions: sessions,
            scheduler: ${jsonEncode(scheduler)},
            observability: ${jsonEncode(observability)},
          );
        },
      );
}
''';

  static String _renderSessionModule() =>
      '''// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v2.

import 'package:dartitect_flutter/dartitect_flutter.dart';

/// Tooling-materialized session composition module.
abstract final class SessionModule {
  static SessionRuntimeController<R, D> create<R, D extends Object>() =>
      SessionRuntimeController<R, D>();
}
''';

  static String _renderDrift(String name) {
    final type = _pascal(name);
    return '''// GENERATED CODE - DO NOT EDIT BY HAND.
// Operational schema only; domain tables and queries remain consumer-owned.

import 'package:dartitect_drift/dartitect_drift.dart';

const int ${name}DartitectDriftSchemaVersion = 1;

class ${type}DartitectOutboxRows extends Table {
  TextColumn get id => text()();
  TextColumn get dataset => text()();
  TextColumn get idempotencyKey => text().unique()();
  BlobColumn get payload => blob()();
  TextColumn get state => text()();
  IntColumn get attempt => integer().withDefault(const Constant<int>(0))();
  IntColumn get createdAtMicros => integer()();
  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

class ${type}DartitectCheckpointRows extends Table {
  TextColumn get dataset => text()();
  BlobColumn get checkpoint => blob()();
  IntColumn get fencingToken => integer().nullable()();
  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{dataset};
}

class ${type}DartitectJournalRows extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get attemptId => text()();
  IntColumn get sequence => integer()();
  TextColumn get fact => text()();
  IntColumn get recordedAtMicros => integer()();
}

class ${type}DartitectLeaseRows extends Table {
  TextColumn get dataset => text()();
  TextColumn get owner => text()();
  IntColumn get fencingToken => integer()();
  IntColumn get expiresAtMicros => integer()();
  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{dataset};
}

class ${type}DartitectReceiptRows extends Table {
  TextColumn get operationId => text()();
  TextColumn get status => text()();
  IntColumn get recordedAtMicros => integer()();
  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{operationId};
}

class ${type}DartitectTransferCheckpointRows extends Table {
  TextColumn get transferId => text()();
  IntColumn get committedOffset => integer()();
  IntColumn get revision => integer()();
  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{transferId};
}
''';
  }

  static String _renderObjectBox(String name) {
    final type = _pascal(name);
    int uid(String value) => _stableUid('$name/$value');
    return '''// GENERATED CODE - DO NOT EDIT BY HAND.
// Provider exception: mutable ObjectBox 5.3.2 entities require classic fields.
// UIDs are deterministic and must remain preserved by wiring sync.

import 'package:dartitect_objectbox/dartitect_objectbox.dart';

const int ${name}DartitectObjectBoxSchemaVersion = 1;

@Entity(uid: ${uid('outbox')})
final class ${type}DartitectOutboxEntity {
  ${type}DartitectOutboxEntity({this.id = 0, required this.operationId,
      required this.dataset, required this.idempotencyKey,
      required this.payload, required this.state, this.attempt = 0});
  @Id() int id;
  @Property(uid: ${uid('outbox/operationId')}) String operationId;
  @Property(uid: ${uid('outbox/dataset')}) String dataset;
  @Property(uid: ${uid('outbox/idempotencyKey')}) String idempotencyKey;
  @Property(uid: ${uid('outbox/payload')}) List<int> payload;
  @Property(uid: ${uid('outbox/state')}) String state;
  @Property(uid: ${uid('outbox/attempt')}) int attempt;
}

@Entity(uid: ${uid('checkpoint')})
final class ${type}DartitectCheckpointEntity {
  ${type}DartitectCheckpointEntity({this.id = 0, required this.dataset,
      required this.checkpoint, this.fencingToken = 0});
  @Id() int id;
  @Property(uid: ${uid('checkpoint/dataset')}) String dataset;
  @Property(uid: ${uid('checkpoint/value')}) List<int> checkpoint;
  @Property(uid: ${uid('checkpoint/fencing')}) int fencingToken;
}

@Entity(uid: ${uid('journal')})
final class ${type}DartitectJournalEntity {
  ${type}DartitectJournalEntity({this.id = 0, required this.attemptId,
      required this.sequence, required this.fact,
      required this.recordedAtMicros});
  @Id() int id;
  @Property(uid: ${uid('journal/attemptId')}) String attemptId;
  @Property(uid: ${uid('journal/sequence')}) int sequence;
  @Property(uid: ${uid('journal/fact')}) String fact;
  @Property(uid: ${uid('journal/recordedAt')}) int recordedAtMicros;
}

@Entity(uid: ${uid('lease')})
final class ${type}DartitectLeaseEntity {
  ${type}DartitectLeaseEntity({this.id = 0, required this.dataset,
      required this.owner, required this.fencingToken,
      required this.expiresAtMicros});
  @Id() int id;
  @Property(uid: ${uid('lease/dataset')}) String dataset;
  @Property(uid: ${uid('lease/owner')}) String owner;
  @Property(uid: ${uid('lease/fencing')}) int fencingToken;
  @Property(uid: ${uid('lease/expiry')}) int expiresAtMicros;
}

@Entity(uid: ${uid('receipt')})
final class ${type}DartitectReceiptEntity {
  ${type}DartitectReceiptEntity({this.id = 0, required this.operationId,
      required this.status, required this.recordedAtMicros});
  @Id() int id;
  @Property(uid: ${uid('receipt/operationId')}) String operationId;
  @Property(uid: ${uid('receipt/status')}) String status;
  @Property(uid: ${uid('receipt/recordedAt')}) int recordedAtMicros;
}

@Entity(uid: ${uid('transfer')})
final class ${type}DartitectTransferCheckpointEntity {
  ${type}DartitectTransferCheckpointEntity({this.id = 0,
      required this.transferId, required this.committedOffset,
      required this.revision});
  @Id() int id;
  @Property(uid: ${uid('transfer/id')}) String transferId;
  @Property(uid: ${uid('transfer/offset')}) int committedOffset;
  @Property(uid: ${uid('transfer/revision')}) int revision;
}
''';
  }

  static String _renderDio(String name) {
    final type = _pascal(name);
    return '''// GENERATED CODE - DO NOT EDIT BY HAND.

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_dio/dartitect_dio.dart';

/// Owned Dio client with deadlines, typed failures, tracing hooks, and cancellation.
final class ${type}DioModule implements Disposable {
  ${type}DioModule._(this.owner, this.client);

  factory ${type}DioModule.create({
    required Duration connectTimeout,
    required Duration receiveTimeout,
    Iterable<Interceptor> interceptors = const <Interceptor>[],
  }) {
    final owner = DioOwner.create(
      options: BaseOptions(
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
      ),
      interceptors: interceptors,
    );
    return ${type}DioModule._(owner, DefaultDioJsonClient(owner.dio));
  }

  final DioOwner owner;
  final DioJsonClient client;

  CancelToken cancellation(CancellationSignal signal) =>
      bindCancelToken(signal);

  @override
  void dispose() => owner.dispose();
}
''';
  }

  static String _renderWorkmanager(String name) {
    final type = _pascal(name);
    return '''// GENERATED CODE - DO NOT EDIT BY HAND.

import 'package:dartitect_workmanager/dartitect_workmanager.dart';

/// Versioned headless envelope factory for the $type feature.
abstract final class ${type}WorkmanagerJob {
  static DartitectWorkmanagerEnvelope create({
    required String jobId,
    required DateTime deadline,
    Map<String, Object?> payload = const <String, Object?>{},
  }) => DartitectWorkmanagerEnvelope(
    jobId: jobId,
    definition: '$name',
    deadline: deadline,
    payload: payload,
  );
}
''';
  }

  static int _stableUid(String value) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  static String _pascal(String value) => value
      .split('_')
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join();

  static String _renderStringList(Iterable<String> values) {
    final materialized = values.toList(growable: false);
    if (materialized.isEmpty) return '<String>[]';
    return "<String>[\n${materialized.map((value) => "    '$value',").join('\n')}\n  ]";
  }

  static String _join(String left, String right) =>
      '$left${Platform.pathSeparator}${right.replaceAll('/', Platform.pathSeparator)}';
}
