import 'dart:convert';
import 'dart:io';

const _profiles = <String>[
  'local',
  'online',
  'cache',
  'replica',
  'offline-full',
];

Future<void> main(List<String> arguments) async {
  if (arguments.any((argument) => argument != '--fresh')) {
    throw ArgumentError('Usage: materialize_large_consumer.dart [--fresh]');
  }
  final root = Directory.current.absolute;
  if (arguments.contains('--fresh')) await _removeManagedOutputs(root);
  final features = <_Feature>[];
  for (final profile in _profiles) {
    final stem = profile.replaceAll('-', '_');
    for (final scope in const <String>['application', 'session']) {
      for (var index = 1; index <= 3; index += 1) {
        features.add(_Feature('${stem}_${scope}_$index', profile, scope));
      }
    }
  }
  if (features.length != 30) throw StateError('Expected 30 features.');

  await _write(root, 'dartitect.json', _config(features));
  await _write(root, 'contracts/app_api.json', _contract);
  await _write(root, 'lib/large_factories.dart', _factories(features));
  await _write(root, 'lib/all_features.dart', _registry(features));
  await _write(root, 'lib/presentation/large_app.dart', _app);
  await _write(root, 'lib/main.dart', _main);
  await _write(root, 'test/large_consumer_test.dart', _test(features));
  final format = await Process.run(Platform.resolvedExecutable, const <String>[
    'format',
    'lib/large_factories.dart',
    'test/large_consumer_test.dart',
  ], workingDirectory: root.path);
  if (format.exitCode != 0) {
    throw StateError('Large consumer formatting failed: ${format.stderr}');
  }
}

Future<void> _removeManagedOutputs(Directory root) async {
  for (final path in <String>[
    '.dartitect/generation/wiring',
    '.dartitect/generation/contracts',
  ]) {
    final directory = Directory('${root.path}/$path');
    if (await directory.exists()) await directory.delete(recursive: true);
  }
  for (final base in <String>['lib', 'test/support']) {
    final directory = Directory('${root.path}/$base');
    if (!await directory.exists()) continue;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File &&
          (entity.path.endsWith('.wiring.dartitect.g.dart') ||
              entity.path.endsWith('.contracts.dartitect.g.dart'))) {
        await entity.delete();
      }
    }
  }
}

Future<void> _write(Directory root, String path, String content) async {
  final file = File('${root.path}/$path');
  await file.parent.create(recursive: true);
  await file.writeAsString(content.endsWith('\n') ? content : '$content\n');
}

String _config(List<_Feature> features) {
  final declarations = <String, Object?>{};
  const capabilities = <String>[
    'credentials',
    'attachments',
    'forms',
    'queries',
  ];
  for (var serial = 0; serial < features.length; serial += 1) {
    final feature = features[serial];
    final persisted = feature.profile != 'online';
    final remote = feature.profile != 'local';
    final synchronized =
        feature.profile == 'replica' || feature.profile == 'offline-full';
    final contextPrefix = feature.scope == 'application' ? 'app' : 'session';
    declarations[feature.name] = <String, Object?>{
      'profile': feature.profile,
      'scope': feature.scope,
      'factorySource': <String, Object?>{
        'source': 'lib/large_factories.dart',
        'declaration': '${feature.type}Factory',
      },
      'localAuthority': persisted ? 'generated_pull' : 'custom',
      if (persisted) 'storageContext': '${contextPrefix}_storage',
      if (persisted)
        'dataset': <String, Object?>{
          'dataset': feature.name,
          'partition': 'default_partition',
          'codec': '${feature.name}_v1',
          'retention': 'indefinite',
          'transactionBoundary': '${feature.name}_transaction',
        },
      if (remote) 'transport': '${contextPrefix}_api',
      'targets': <String>['linux', 'web'],
      'pagination': remote ? 'cursor' : 'none',
      'diagnostics': serial.isEven ? 'basic' : 'full',
      'headlessTargets': synchronized ? <String>['linux', 'web'] : <String>[],
      'capabilities': <String>[capabilities[serial % capabilities.length]],
      'operations': remote && feature.scope == 'application' && serial % 3 == 0
          ? <Object?>[
              <String, Object?>{
                'contract': 'app_api',
                'operationId': 'getProbe',
              },
            ]
          : <Object?>[],
    };
  }
  final value = <String, Object?>{
    'configVersion': 3,
    'profile': 'native_strict',
    'layers': <String, Object?>{
      'domain': <String>['**/domain/**'],
      'application': <String>['**/application/**'],
      'data': <String>['**/data/**'],
      'infrastructure': <String>['**/infrastructure/**'],
      'presentation': <String>['**/presentation/**'],
    },
    'compositionRoots': <String>[
      'lib/main.dart',
      'test/**',
      '**/composition/**',
    ],
    'generatedInfrastructure': <String>['**/infrastructure/**/*.g.dart'],
    'generatedSuffixes': <String>['.g.dart', '.dartitect.g.dart'],
    'suppressions': <Object?>[],
    'targets': <String, Object?>{
      'platforms': <String>['linux', 'web'],
    },
    'storageContexts': <String, Object?>{
      'app_storage': _context(
        provider: 'drift',
        scope: 'application',
        declaration: 'AppStorageFactory',
      ),
      'session_storage': _context(
        provider: 'drift',
        scope: 'session',
        declaration: 'SessionStorageFactory',
      ),
    },
    'transports': <String, Object?>{
      'app_api': _context(
        provider: 'dio',
        scope: 'application',
        declaration: 'AppTransportFactory',
      ),
      'session_api': _context(
        provider: 'dio',
        scope: 'session',
        declaration: 'SessionTransportFactory',
      ),
    },
    'session': <String, Object?>{
      'factorySource': <String, Object?>{
        'source': 'lib/large_factories.dart',
        'declaration': 'LargeSessionFactory',
      },
    },
    'contracts': <String, Object?>{
      'app_api': <String, Object?>{
        'spec': 'contracts/app_api.json',
        'output': 'lib/contracts/app_api.contracts.dartitect.g.dart',
        'transport': 'app_api',
      },
    },
    'observability': <String, Object?>{'provider': 'developer'},
    'scheduler': <String, Object?>{
      'provider': 'workmanager',
      'targets': <String>['linux', 'web'],
    },
    'features': <String, Object?>{'declarations': declarations},
    'extensionSources': <Object?>[],
  };
  return '${const JsonEncoder.withIndent('  ').convert(value)}\n';
}

Map<String, Object?> _context({
  required String provider,
  required String scope,
  required String declaration,
}) => <String, Object?>{
  'provider': provider,
  if (provider == 'drift') 'mode': 'durable',
  'scope': scope,
  'factorySource': <String, Object?>{
    'source': 'lib/large_factories.dart',
    'declaration': declaration,
  },
  'targets': <String>['linux', 'web'],
};

String _factories(List<_Feature> features) {
  final buffer = StringBuffer()
    ..writeln('// ignore_for_file: public_member_api_docs')
    ..writeln()
    ..writeln("import 'dart:async';")
    ..writeln()
    ..writeln("import 'package:dartitect/dartitect.dart';")
    ..writeln("import 'package:dartitect_dio/dartitect_dio.dart';")
    ..writeln(
      "import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';",
    )
    ..writeln("import 'package:dartitect_sync/dartitect_sync.dart';")
    ..writeln()
    ..writeln('abstract final class LargeCensus {')
    ..writeln('  static int liveContexts = 0;')
    ..writeln('  static int appStorageOpens = 0;')
    ..writeln('  static int sessionStorageOpens = 0;')
    ..writeln('  static int appTransportOpens = 0;')
    ..writeln('  static int sessionTransportOpens = 0;')
    ..writeln('  static int sessionCreates = 0;')
    ..writeln('}')
    ..writeln()
    ..writeln('final class LargeFailure implements Exception {')
    ..writeln('  const LargeFailure(this.code);')
    ..writeln('  final String code;')
    ..writeln('}')
    ..writeln()
    ..writeln('final class LargeMutation {')
    ..writeln('  const LargeMutation(this.value);')
    ..writeln('  final String value;')
    ..writeln('}')
    ..writeln()
    ..writeln('abstract interface class LargeLocalPort {')
    ..writeln('  Stream<void> watch();')
    ..writeln(
      '  Future<Result<List<String>, LargeFailure>> read(CancellationSignal cancellation);',
    )
    ..writeln('}')
    ..writeln()
    ..writeln('base class LargeStorage')
    ..writeln('    implements LargeLocalPort,')
    ..writeln(
      '        MutationOutboxStore<String, LargeMutation, LargeFailure> {',
    )
    ..writeln('  LargeStorage() { LargeCensus.liveContexts += 1; }')
    ..writeln('  final StreamController<void> _changes =')
    ..writeln('      StreamController<void>.broadcast();')
    ..writeln(
      '  final LargeCheckpointStore checkpoints = LargeCheckpointStore();',
    )
    ..writeln(
      '  final Map<String, OutboxOperation<String, LargeMutation>> _outbox =',
    )
    ..writeln('      <String, OutboxOperation<String, LargeMutation>>{};')
    ..writeln('  bool disposed = false;')
    ..writeln('  @override')
    ..writeln('  Stream<void> watch() => _changes.stream;')
    ..writeln('  @override')
    ..writeln('  Future<Result<List<String>, LargeFailure>> read(')
    ..writeln('    CancellationSignal cancellation,')
    ..writeln('  ) async {')
    ..writeln('    cancellation.throwIfCancelled();')
    ..writeln("    return const Ok<List<String>>(<String>['large']);")
    ..writeln('  }')
    ..writeln('  @override')
    ..writeln('  Future<Result<void, LargeFailure>> applyLocalAndEnqueue(')
    ..writeln('    OutboxOperation<String, LargeMutation> operation,')
    ..writeln('    CancellationSignal signal,')
    ..writeln('  ) async {')
    ..writeln('    signal.throwIfCancelled();')
    ..writeln('    _outbox[operation.idempotencyKey] = operation;')
    ..writeln('    _changes.add(null);')
    ..writeln('    return const Ok<void>(null);')
    ..writeln('  }')
    ..writeln('  @override')
    ..writeln('  Future<Result<void, LargeFailure>> markState(')
    ..writeln('    OutboxOperation<String, LargeMutation> operation,')
    ..writeln('    CancellationSignal signal,')
    ..writeln('  ) async {')
    ..writeln('    signal.throwIfCancelled();')
    ..writeln('    _outbox[operation.idempotencyKey] = operation;')
    ..writeln('    return const Ok<void>(null);')
    ..writeln('  }')
    ..writeln('  @override')
    ..writeln(
      '  Future<Result<List<OutboxOperation<String, LargeMutation>>, LargeFailure>>',
    )
    ..writeln('  loadRecoverable(CancellationSignal signal) async {')
    ..writeln('    signal.throwIfCancelled();')
    ..writeln('    return Ok<List<OutboxOperation<String, LargeMutation>>>(')
    ..writeln(
      '      List<OutboxOperation<String, LargeMutation>>.unmodifiable(_outbox.values),',
    )
    ..writeln('    );')
    ..writeln('  }')
    ..writeln('  @override')
    ..writeln('  Future<Result<void, LargeFailure>> compensate(')
    ..writeln('    OutboxOperation<String, LargeMutation> operation,')
    ..writeln('    CancellationSignal signal,')
    ..writeln('  ) async => const Ok<void>(null);')
    ..writeln('  Future<void> close() async {')
    ..writeln('    if (disposed) return;')
    ..writeln('    disposed = true;')
    ..writeln('    LargeCensus.liveContexts -= 1;')
    ..writeln('    await _changes.close();')
    ..writeln('  }')
    ..writeln('}')
    ..writeln()
    ..writeln('final class LargeCheckpointStore')
    ..writeln('    implements SyncCheckpointStore<String, int> {')
    ..writeln('  final Map<String, int> _values = <String, int>{};')
    ..writeln('  @override')
    ..writeln(
      '  Future<int?> read(String key, CancellationSignal signal) async {',
    )
    ..writeln('    signal.throwIfCancelled();')
    ..writeln('    return _values[key];')
    ..writeln('  }')
    ..writeln('  @override')
    ..writeln('  Future<void> write(String key, int checkpoint,')
    ..writeln('      CancellationSignal signal, {int? fencingToken}) async {')
    ..writeln('    signal.throwIfCancelled();')
    ..writeln('    _values[key] = checkpoint;')
    ..writeln('  }')
    ..writeln('  @override')
    ..writeln(
      '  Future<void> remove(String key, CancellationSignal signal) async {',
    )
    ..writeln('    signal.throwIfCancelled();')
    ..writeln('    _values.remove(key);')
    ..writeln('  }')
    ..writeln('}')
    ..writeln()
    ..writeln('final class AppStorage extends LargeStorage {}')
    ..writeln('final class SessionStorage extends LargeStorage {}')
    ..writeln()
    ..writeln("@DartitectApplicationContextFactory('app_storage')")
    ..writeln('final class AppStorageFactory {')
    ..writeln('  Future<AppStorage> open() async {')
    ..writeln('    LargeCensus.appStorageOpens += 1;')
    ..writeln('    return AppStorage();')
    ..writeln('  }')
    ..writeln('  Future<void> dispose(AppStorage value) => value.close();')
    ..writeln('}')
    ..writeln()
    ..writeln("@DartitectSessionContextFactory('session_storage')")
    ..writeln('final class SessionStorageFactory {')
    ..writeln('  Future<SessionStorage> open() async {')
    ..writeln('    LargeCensus.sessionStorageOpens += 1;')
    ..writeln('    return SessionStorage();')
    ..writeln('  }')
    ..writeln('  Future<void> dispose(SessionStorage value) => value.close();')
    ..writeln('}')
    ..writeln()
    ..writeln('base class LargeTransport implements Disposable {')
    ..writeln('  LargeTransport(this.owner) {')
    ..writeln('    LargeCensus.liveContexts += 1;')
    ..writeln('  }')
    ..writeln('  final DioOwner owner;')
    ..writeln('  DioJsonClient get client => DefaultDioJsonClient(owner.dio);')
    ..writeln('  bool disposed = false;')
    ..writeln('  @override')
    ..writeln('  void dispose() {')
    ..writeln('    if (disposed) return;')
    ..writeln('    disposed = true;')
    ..writeln('    owner.dispose();')
    ..writeln('    LargeCensus.liveContexts -= 1;')
    ..writeln('  }')
    ..writeln('}')
    ..writeln('final class AppTransport extends LargeTransport {')
    ..writeln('  AppTransport(super.owner);')
    ..writeln('}')
    ..writeln('final class SessionTransport extends LargeTransport {')
    ..writeln('  SessionTransport(super.owner);')
    ..writeln('}')
    ..writeln()
    ..writeln("@DartitectTransportContextFactory('app_api')")
    ..writeln('final class AppTransportFactory {')
    ..writeln('  AppTransport open() {')
    ..writeln('    LargeCensus.appTransportOpens += 1;')
    ..writeln('    return AppTransport(DioOwner.create());')
    ..writeln('  }')
    ..writeln('  DioJsonClient client(AppTransport value) => value.client;')
    ..writeln('  void dispose(AppTransport value) => value.dispose();')
    ..writeln('}')
    ..writeln()
    ..writeln("@DartitectTransportContextFactory('session_api')")
    ..writeln('final class SessionTransportFactory {')
    ..writeln('  SessionTransport open() {')
    ..writeln('    LargeCensus.sessionTransportOpens += 1;')
    ..writeln('    return SessionTransport(DioOwner.create());')
    ..writeln('  }')
    ..writeln('  void dispose(SessionTransport value) => value.dispose();')
    ..writeln('}')
    ..writeln()
    ..writeln('final class LargeSession { const LargeSession(); }')
    ..writeln('@DartitectSessionFactory()')
    ..writeln('final class LargeSessionFactory {')
    ..writeln('  LargeSession create() {')
    ..writeln('    LargeCensus.sessionCreates += 1;')
    ..writeln('    return const LargeSession();')
    ..writeln('  }')
    ..writeln('}')
    ..writeln()
    ..writeln('final class LargeRemotePort {')
    ..writeln('  const LargeRemotePort(this.transport);')
    ..writeln('  final LargeTransport transport;')
    ..writeln('}')
    ..writeln('final class LargeMapper { const LargeMapper(); }')
    ..writeln('final class LargeRepository implements AsyncDisposable {')
    ..writeln(
      '  LargeRepository(Iterable<Object> seams) : seams = List<Object>.of(seams);',
    )
    ..writeln('  final List<Object> seams;')
    ..writeln('  bool disposed = false;')
    ..writeln('  @override')
    ..writeln('  Future<void> disposeAsync() async { disposed = true; }')
    ..writeln('}')
    ..writeln('final class LargeViewModel implements AsyncDisposable {')
    ..writeln('  const LargeViewModel(this.repository);')
    ..writeln('  final LargeRepository repository;')
    ..writeln('  @override')
    ..writeln('  Future<void> disposeAsync() async {}')
    ..writeln('}')
    ..writeln()
    ..writeln('final class LargeIdempotencyPolicy')
    ..writeln(
      '    implements MutationIdempotencyPolicy<String, LargeMutation> {',
    )
    ..writeln('  const LargeIdempotencyPolicy();')
    ..writeln('  @override')
    ..writeln(
      "  String create(String key, LargeMutation argument) => 'large:\$key:\${argument.value}';",
    )
    ..writeln('}')
    ..writeln('final class LargeConflictPolicy')
    ..writeln('    implements MutationConflictPolicy<String> {')
    ..writeln('  const LargeConflictPolicy();')
    ..writeln('  @override')
    ..writeln('  String resolve(String local, String remote) => local;')
    ..writeln('}')
    ..writeln();

  for (final feature in features) {
    _writeFactory(buffer, feature);
  }
  return buffer.toString();
}

void _writeFactory(StringBuffer buffer, _Feature feature) {
  final persisted = feature.profile != 'online';
  final remote = feature.profile != 'local';
  final synchronized =
      feature.profile == 'replica' || feature.profile == 'offline-full';
  final offline = feature.profile == 'offline-full';
  final storageType = feature.scope == 'application'
      ? 'AppStorage'
      : 'SessionStorage';
  final transportType = feature.scope == 'application'
      ? 'AppTransport'
      : 'SessionTransport';
  final type = feature.type;
  buffer
    ..writeln("@DartitectFeatureFactory('${feature.name}')")
    ..writeln('final class ${type}Factory {')
    ..writeln('  const ${type}Factory();');
  if (persisted) {
    buffer
      ..writeln(
        '  LargeLocalPort createLocalPort($storageType storage) => storage;',
      )
      ..writeln(
        '  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();',
      )
      ..writeln('  Future<Result<List<String>, LargeFailure>> read(')
      ..writeln(
        '    LargeLocalPort localPort, CancellationSignal cancellation,',
      )
      ..writeln('  ) => localPort.read(cancellation);');
  }
  if (remote) {
    buffer
      ..writeln(
        '  LargeRemotePort createRemotePort($transportType transport) =>',
      )
      ..writeln('      LargeRemotePort(transport);')
      ..writeln('  LargeMapper createMapper() => const LargeMapper();');
  }
  if (synchronized) {
    buffer
      ..writeln('  SyncDataset<String, int, LargeFailure> createDataset() =>')
      ..writeln('      SyncDataset<String, int, LargeFailure>(')
      ..writeln("        key: '${feature.name}',")
      ..writeln(
        '        synchronize: (context) async => Ok<SyncDatasetOutcome<int>>(',
      )
      ..writeln(
        '          SyncDatasetOutcome<int>.checkpoint((context.checkpoint ?? 0) + 1),',
      )
      ..writeln('        ),')
      ..writeln('      );')
      ..writeln('  SyncCheckpointStore<String, int> createCheckpointStore(')
      ..writeln('    $storageType storage,')
      ..writeln('  ) => storage.checkpoints;');
  }
  if (offline) {
    buffer
      ..writeln('  MutationOutboxStore<String, LargeMutation, LargeFailure>')
      ..writeln('  createOutboxStore($storageType storage) => storage;')
      ..writeln('  MutationIdempotencyPolicy<String, LargeMutation>')
      ..writeln(
        '  createIdempotencyPolicy() => const LargeIdempotencyPolicy();',
      )
      ..writeln('  MutationConflictPolicy<String> createConflictPolicy() =>')
      ..writeln('      const LargeConflictPolicy();')
      ..writeln('  Future<Result<void, LargeFailure>> synchronizeMutation(')
      ..writeln('    LargeRemotePort remotePort,')
      ..writeln('    OutboxOperation<String, LargeMutation> operation,')
      ..writeln('    CancellationSignal cancellation,')
      ..writeln('  ) async {')
      ..writeln('    cancellation.throwIfCancelled();')
      ..writeln('    return const Ok<void>(null);')
      ..writeln('  }')
      ..writeln('  MutationFailurePolicy classifyMutationFailure(')
      ..writeln('    LargeFailure failure,')
      ..writeln('  ) => const MutationFailurePolicy.queued();');
  }
  final parameters = <String>[
    if (persisted) 'LargeLocalPort localPort',
    if (remote) 'LargeRemotePort remotePort',
    if (remote) 'LargeMapper mapper',
    if (persisted)
      'PullReactiveSource<List<String>, LargeFailure> localAuthority',
    if (synchronized) 'SyncEngine<String, int, LargeFailure> syncEngine',
  ];
  buffer.writeln('  LargeRepository createRepository(');
  for (final parameter in parameters) {
    buffer.writeln('    $parameter,');
  }
  buffer
    ..writeln('  ) => LargeRepository(<Object>[')
    ..writeln(
      '    ${parameters.map((value) => value.split(' ').last).join(', ')}',
    )
    ..writeln('  ]);')
    ..writeln('  LargeViewModel createViewModel(LargeRepository repository) =>')
    ..writeln('      LargeViewModel(repository);')
    ..writeln('}')
    ..writeln();
}

String _registry(List<_Feature> features) {
  final buffer = StringBuffer()
    ..writeln(
      '// Materialized canary registry; feature wiring remains generated.',
    )
    ..writeln('// ignore_for_file: public_member_api_docs')
    ..writeln();
  final sorted = features.toList()
    ..sort((left, right) => left.name.compareTo(right.name));
  for (final feature in sorted) {
    buffer.writeln(
      "export 'features/${feature.name}/composition/${feature.name}.wiring.dartitect.g.dart';",
    );
  }
  buffer
    ..writeln()
    ..writeln('const List<String> largeFeatureNames = <String>[');
  for (final feature in features) {
    buffer.writeln("  '${feature.name}',");
  }
  buffer.writeln('];');
  return buffer.toString();
}

String _test(List<_Feature> features) {
  final buffer = StringBuffer()
    ..writeln("import 'package:dartitect/dartitect.dart';")
    ..writeln("import 'package:dartitect_testing/dartitect_testing.dart';")
    ..writeln("import 'package:flutter_test/flutter_test.dart';")
    ..writeln("import 'package:large_consumer_canary/all_features.dart';")
    ..writeln(
      "import 'package:large_consumer_canary/contracts/app_api.contracts.dartitect.g.dart';",
    )
    ..writeln(
      "import 'package:large_consumer_canary/composition/application_module.wiring.dartitect.g.dart';",
    )
    ..writeln(
      "import 'package:large_consumer_canary/composition/session_module.wiring.dartitect.g.dart';",
    )
    ..writeln("import 'package:large_consumer_canary/large_factories.dart';")
    ..writeln()
    ..writeln('void main() {')
    ..writeln(
      "  test('30 concrete feature graphs open and close with exact scopes', () async {",
    )
    ..writeln('    expect(largeFeatureNames, hasLength(30));')
    ..writeln('    final census = ResourceCensus();')
    ..writeln("    final appLease = census.acquire('application');")
    ..writeln('    final coordinator = ApplicationModule.create();')
    ..writeln('    final attempt = await coordinator.run();')
    ..writeln('    final application =')
    ..writeln(
      '        (attempt as BootstrapSucceeded<ApplicationGraph>).graph;',
    )
    ..writeln('    expect(LargeCensus.appStorageOpens, 1);')
    ..writeln('    expect(LargeCensus.appTransportOpens, 1);')
    ..writeln(
      '    final session = await ResourceTransaction.create<SessionGraph>(',
    )
    ..writeln(
      '      (transaction) => SessionModule.create(application.root, transaction),',
    )
    ..writeln('    );')
    ..writeln("    final sessionLease = census.acquire('session');")
    ..writeln('    expect(LargeCensus.sessionStorageOpens, 1);')
    ..writeln('    expect(LargeCensus.sessionTransportOpens, 1);')
    ..writeln('    expect(LargeCensus.sessionCreates, 1);');
  for (final feature in features) {
    final parent = feature.scope == 'application'
        ? 'application.root'
        : 'session.root';
    final variable = feature.name.replaceAll('_', '');
    buffer
      ..writeln(
        '    final $variable = await ResourceTransaction.create<${feature.type}Runtime>(',
      )
      ..writeln('      (transaction) => ${feature.type}Runtime.create(')
      ..writeln('        $parent, const ${feature.type}Factory(), transaction,')
      ..writeln('      ),')
      ..writeln('    );')
      ..writeln(
        "    expect(${feature.type}FeatureWiring.profile, '${feature.profile}');",
      );
    if (feature.name == 'online_application_1') {
      buffer.writeln(
        '    expect($variable.root.appApiGetProbe, isA<GetProbeOperation>());',
      );
    }
    buffer.writeln('    await $variable.disposeAsync();');
  }
  buffer
    ..writeln('    await session.disposeAsync();')
    ..writeln('    sessionLease.dispose();')
    ..writeln('    expect(session.root.sessionStorage.disposed, isTrue);')
    ..writeln('    expect(session.root.sessionApi.disposed, isTrue);')
    ..writeln(
      '    final replacement = await ResourceTransaction.create<SessionGraph>(',
    )
    ..writeln(
      '      (transaction) => SessionModule.create(application.root, transaction),',
    )
    ..writeln('    );')
    ..writeln('    expect(LargeCensus.sessionCreates, 2);')
    ..writeln('    await replacement.disposeAsync();')
    ..writeln('    expect(application.root.appStorage.disposed, isFalse);')
    ..writeln('    await application.disposeAsync();')
    ..writeln('    appLease.dispose();')
    ..writeln('    await coordinator.disposeAsync();')
    ..writeln('    expect(LargeCensus.liveContexts, 0);')
    ..writeln('    census.verifyZero();')
    ..writeln('  });')
    ..writeln('}');
  return buffer.toString();
}

const _contract = '''{
  "openapi": "3.1.0",
  "info": {"title": "Large Probe", "version": "1"},
  "paths": {
    "/probe/{id}": {
      "get": {
        "operationId": "getProbe",
        "parameters": [
          {"name": "id", "in": "path", "required": true,
           "schema": {"type": "string"}}
        ],
        "responses": {
          "200": {"description": "ok"},
          "404": {"description": "missing"}
        }
      }
    }
  }
}''';

const _app = '''// ignore_for_file: public_member_api_docs

import 'package:flutter/widgets.dart';

import '../all_features.dart';

final class LargeConsumerApp extends StatelessWidget {
  const LargeConsumerApp({super.key});

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: Text('Large graphs: \${largeFeatureNames.length}')),
  );
}
''';

const _main = '''import 'package:dartitect_flutter/dartitect_flutter.dart';

import 'composition/application_module.wiring.dartitect.g.dart';
import 'presentation/large_app.dart';

void main() => runDartitectApplication<ApplicationGraph>(
  create: ApplicationModule.create,
  application: (_) => const LargeConsumerApp(),
);
''';

final class _Feature {
  const _Feature(this.name, this.profile, this.scope);

  final String name;
  final String profile;
  final String scope;

  String get type => name
      .split('_')
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join();
}
