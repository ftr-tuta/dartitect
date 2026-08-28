import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dart_mcp/client.dart';
import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:dartitect_mcp/dartitect_mcp.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  group('DartitectMcpServer', () {
    test('policy rejects authorization of the filesystem root', () {
      expect(
        () => DartitectMcpPolicy(
          allowedRoots: <Directory>[Directory(Platform.pathSeparator)],
        ),
        throwsArgumentError,
      );
    });

    test('rejects invalid injected plan identifiers', () async {
      final project = await _project();
      final environment = _Environment(
        DartitectMcpPolicy(
          allowedRoots: <Directory>[project],
          createPlanId: () => 'short',
        ),
      );
      addTearDown(environment.close);
      await environment.initialize();

      final result = await environment.call('dartitect_preview_init');
      expect(_errorCode(result), 'plan_id_unavailable');
    });

    test(
      'negotiates instructions and exposes only the closed tool set',
      () async {
        final project = await _project();
        final environment = _Environment(
          DartitectMcpPolicy(allowedRoots: <Directory>[project]),
        );
        addTearDown(environment.close);

        final initialized = await environment.initialize();
        expect(initialized.instructions, contains('read-only by default'));
        expect(initialized.capabilities.tools, isNotNull);
        expect(initialized.capabilities.resources, isNotNull);

        final tools = (await environment.connection.listTools()).tools;
        expect(
          tools.map((tool) => tool.name),
          containsAll(<String>[
            'dartitect_inspect_project',
            'dartitect_scan_architecture',
            'dartitect_doctor_project',
            'dartitect_explain_finding',
            'dartitect_audit_conformance',
            'dartitect_verify_project',
            'dartitect_preview_init',
            'dartitect_preview_baseline',
            'dartitect_preview_codex_sync',
            'dartitect_preview_model_sync',
            'dartitect_preview_model_primary_migration',
            'dartitect_apply_change',
          ]),
        );
        expect(tools, hasLength(12));
        expect(
          tools.map((tool) => tool.name).join(' '),
          isNot(contains('create')),
        );
        final apply = tools.singleWhere(
          (tool) => tool.name == 'dartitect_apply_change',
        );
        expect(apply.toolAnnotations?.readOnlyHint, isFalse);
        expect(apply.toolAnnotations?.destructiveHint, isTrue);
        for (final tool in tools.where((tool) => tool.name != apply.name)) {
          expect(tool.toolAnnotations?.readOnlyHint, isTrue, reason: tool.name);
          expect(tool.outputSchema, isNotNull, reason: tool.name);
        }
      },
    );

    test('returns structured and textual inspect output', () async {
      final project = await _project();
      final environment = _Environment(
        DartitectMcpPolicy(allowedRoots: <Directory>[project]),
      );
      addTearDown(environment.close);
      await environment.initialize();

      final result = await environment.call('dartitect_inspect_project');
      expect(result.isError, isNot(true));
      expect(result.structuredContent?['ok'], isTrue);
      expect(
        (result.structuredContent?['project'] as Map<String, Object?>)['root'],
        '.',
      );
      final text = (result.content.single as TextContent).text;
      expect(jsonDecode(text), result.structuredContent);

      final service = DartitectProjectService(project);
      expect(result.structuredContent, <String, Object?>{
        'ok': true,
        ...(await service.inspectProject()).toJson(),
      });
      final doctor = await environment.call('dartitect_doctor_project');
      expect(doctor.structuredContent, <String, Object?>{
        'ok': true,
        ...(await service.doctorProject()).toJson(),
      });
      final report = await service.scanArchitecture(useBaseline: false);
      final scan = await environment.call(
        'dartitect_scan_architecture',
        <String, Object?>{'baseline': false, 'limit': 500},
      );
      expect(scan.structuredContent?['project'], report.project);
      expect(scan.structuredContent?['capabilities'], report.capabilities);
      expect(scan.structuredContent?['exitCode'], report.exitCode);
      expect(scan.structuredContent?['results'], <Map<String, Object?>>[
        for (final finding in report.findings)
          <String, Object?>{'category': 'finding', ...finding.toJson()},
        for (final violation in report.violations)
          <String, Object?>{'category': 'violation', ...violation.toJson()},
      ]);

      final conformance = await environment.call('dartitect_audit_conformance');
      expect(conformance.structuredContent?['command'], 'conformance audit');
      expect(
        conformance.structuredContent?['canonicalGate'],
        'dartitect scan --no-baseline',
      );
      expect(
        conformance.structuredContent?['support'],
        containsPair('migration', false),
      );
    });

    test(
      'verify tool is read-only and exposes model/provider status',
      () async {
        final project = await _project();
        final before = await File('${project.path}/pubspec.yaml')
            .readAsString();
        final environment = _Environment(
          DartitectMcpPolicy(allowedRoots: <Directory>[project]),
        );
        addTearDown(environment.close);
        await environment.initialize();

        final result = await environment.call('dartitect_verify_project');

        expect(result.isError, isNot(true));
        final projectStatus =
            result.structuredContent?['project'] as Map<String, Object?>;
        expect(projectStatus['modelStatus'], isA<Map<String, Object?>>());
        expect(projectStatus['providerStatus'], isA<Map<String, Object?>>());
        expect(
          await File('${project.path}/pubspec.yaml').readAsString(),
          before,
        );
        expect(File('${project.path}/dartitect.json').existsSync(), isFalse);
      },
    );

    test('paginates scan results within policy limits', () async {
      final project = await _project(
        source:
            "import 'package:flutter/widgets.dart';\nBuildContext? context;\n",
        sourcePath: 'lib/features/example/domain/model.dart',
      );
      final environment = _Environment(
        DartitectMcpPolicy(
          allowedRoots: <Directory>[project],
          defaultResultLimit: 1,
          maxResultLimit: 2,
        ),
      );
      addTearDown(environment.close);
      await environment.initialize();

      final first = await environment.call(
        'dartitect_scan_architecture',
        <String, Object?>{'baseline': false, 'limit': 1},
      );
      final page = first.structuredContent?['page'] as Map<String, Object?>;
      expect(page['returned'], 1);
      expect(page['total'], greaterThanOrEqualTo(2));
      expect(page['nextOffset'], 1);

      final invalid = await environment.call(
        'dartitect_scan_architecture',
        <String, Object?>{'limit': 3},
      );
      expect(invalid.isError, isTrue);
      expect(_errorCode(invalid), 'invalid_input');
    });

    test('rejects absolute paths, traversal, and symlink escape', () async {
      final authorized = await _project();
      final outside = await _project();
      final link = Link('${authorized.path}/outside-link');
      if (!Platform.isWindows) await link.create(outside.path);
      final environment = _Environment(
        DartitectMcpPolicy(allowedRoots: <Directory>[authorized]),
      );
      addTearDown(environment.close);
      await environment.initialize();

      for (final path in <String>['/tmp', '../outside']) {
        final result = await environment.call(
          'dartitect_inspect_project',
          <String, Object?>{'path': path},
        );
        expect(result.isError, isTrue, reason: path);
      }
      if (!Platform.isWindows) {
        final escaped = await environment.call(
          'dartitect_inspect_project',
          <String, Object?>{'path': 'outside-link'},
        );
        expect(_errorCode(escaped), 'symlink_escape');
      }
      expect(environment.diagnostics.toString(), isNot(contains(outside.path)));
    });

    test('supports relative projects with spaces and Unicode', () async {
      final allowed = await Directory.systemTemp.createTemp(
        'dartitect-mcp-allowed-',
      );
      addTearDown(() async {
        if (await allowed.exists()) await allowed.delete(recursive: true);
      });
      final project = Directory('${allowed.path}/projeto ü com espaços');
      await Directory('${project.path}/lib').create(recursive: true);
      await File('${project.path}/pubspec.yaml').writeAsString('''name: fixture
environment:
  sdk: ^3.13.0
''');
      await File('${project.path}/lib/main.dart')
          .writeAsString('void main() {}\n');
      final environment = _Environment(
        DartitectMcpPolicy(allowedRoots: <Directory>[allowed]),
      );
      addTearDown(environment.close);
      await environment.initialize();

      final inspected = await environment.call(
        'dartitect_inspect_project',
        <String, Object?>{'path': 'projeto ü com espaços'},
      );
      expect(inspected.structuredContent?['ok'], isTrue);
      final missing = await environment.call(
        'dartitect_inspect_project',
        <String, Object?>{'path': 'projeto ausente'},
      );
      expect(_errorCode(missing), 'root_not_found');
    });

    test('returns a structured timeout without leaking a path', () async {
      final project = await _project();
      final environment = _Environment(
        DartitectMcpPolicy(
          allowedRoots: <Directory>[project],
          operationTimeout: const Duration(microseconds: 1),
        ),
      );
      addTearDown(environment.close);
      await environment.initialize();

      final result = await environment.call('dartitect_inspect_project');
      expect(_errorCode(result), 'timeout');
      expect(
        jsonEncode(result.structuredContent),
        isNot(contains(project.path)),
      );
    });

    test(
      'resources are generated, bounded, and do not read arbitrary files',
      () async {
        final environment = _Environment(
          DartitectMcpPolicy(allowedRoots: <Directory>[await _project()]),
        );
        addTearDown(environment.close);
        await environment.initialize();

        final resources = await environment.connection.listResources();
        expect(
          resources.resources.map((resource) => resource.uri),
          containsAll(<String>[
            'dartitect://packages',
            'dartitect://config/v1',
          ]),
        );
        final templates = await environment.connection.listResourceTemplates();
        expect(templates.resourceTemplates, hasLength(3));
        final package = await environment.connection.readResource(
          ReadResourceRequest(uri: 'dartitect://packages/dartitect_mcp'),
        );
        final packageText =
            (package.contents.single as TextResourceContents).text;
        expect(packageText, contains('development'));
        final diagnostic = await environment.connection.readResource(
          ReadResourceRequest(uri: 'dartitect://diagnostics/DT1001'),
        );
        expect(
          (diagnostic.contents.single as TextResourceContents).text,
          contains('Domain code imports Flutter'),
        );
      },
    );

    test('writes are disabled by default even after preview', () async {
      final project = await _project();
      final environment = _Environment(
        DartitectMcpPolicy(allowedRoots: <Directory>[project]),
      );
      addTearDown(environment.close);
      await environment.initialize();

      final preview = await environment.call('dartitect_preview_init');
      final planId = preview.structuredContent?['planId']! as String;
      final apply = await environment.call(
        'dartitect_apply_change',
        <String, Object?>{'planId': planId, 'confirmed': true},
      );
      expect(_errorCode(apply), 'writes_disabled');
      expect(File('${project.path}/dartitect.json').existsSync(), isFalse);
    });

    test('applies an opted-in plan once and rejects replay', () async {
      final project = await _project();
      final environment = _Environment(
        DartitectMcpPolicy(
          allowedRoots: <Directory>[project],
          allowWrites: true,
          createPlanId: () => 'deterministic-plan-0001',
        ),
      );
      addTearDown(environment.close);
      await environment.initialize();

      final preview = await environment.call('dartitect_preview_init');
      final planId = preview.structuredContent?['planId']! as String;
      final unconfirmed = await environment.call(
        'dartitect_apply_change',
        <String, Object?>{'planId': planId, 'confirmed': false},
      );
      expect(_errorCode(unconfirmed), 'confirmation_required');
      final applied = await environment.call(
        'dartitect_apply_change',
        <String, Object?>{'planId': planId, 'confirmed': true},
      );
      expect(applied.structuredContent?['ok'], isTrue);
      expect(File('${project.path}/dartitect.json').existsSync(), isTrue);
      final replay = await environment.call(
        'dartitect_apply_change',
        <String, Object?>{'planId': planId, 'confirmed': true},
      );
      expect(_errorCode(replay), 'plan_replayed');
    });

    test(
      'reviews and applies model sync through the shared change gate',
      () async {
        final project = await _modelProject('''
import 'package:dartitect_modeling/dartitect_modeling.dart';

part 'user.dartitect.g.dart';

@DartitectValue()
final class const User({required final String id})
    extends ValueEquality with _\$UserDartitect;
''');
        final environment = _Environment(
          DartitectMcpPolicy(
            allowedRoots: <Directory>[project],
            allowWrites: true,
            createPlanId: () => 'model-sync-plan-0000001',
          ),
        );
        addTearDown(environment.close);
        await environment.initialize();

        final preview = await environment.call('dartitect_preview_model_sync');
        expect(preview.isError, isNot(true));
        final planId = preview.structuredContent?['planId']! as String;
        expect(
          File('${project.path}/lib/user.dartitect.g.dart').existsSync(),
          isFalse,
        );
        final applied = await environment.call(
          'dartitect_apply_change',
          <String, Object?>{'planId': planId, 'confirmed': true},
        );
        expect(applied.structuredContent?['ok'], isTrue);
        expect(
          File('${project.path}/lib/user.dartitect.g.dart').existsSync(),
          isTrue,
        );
      },
    );

    test(
      'primary migration preview is payload-free before reviewed apply',
      () async {
        final project = await _modelProject('''
import 'package:dartitect_modeling/dartitect_modeling.dart';

part 'user.dartitect.g.dart';

@DartitectValue()
final class User extends ValueEquality with _\$UserDartitect {
  const User({required this.id});

  final String id;
}
''');
        final source = File('${project.path}/lib/user.dart');
        final before = await source.readAsString();
        final environment = _Environment(
          DartitectMcpPolicy(
            allowedRoots: <Directory>[project],
            allowWrites: true,
            createPlanId: () => 'model-primary-plan-0001',
          ),
        );
        addTearDown(environment.close);
        await environment.initialize();

        final preview = await environment.call(
          'dartitect_preview_model_primary_migration',
        );

        expect(preview.isError, isNot(true));
        final encoded = jsonEncode(preview.structuredContent);
        expect(encoded, contains('lib/user.dart'));
        expect(encoded, isNot(contains('List<Object?> get equalityProps')));
        expect(await source.readAsString(), before);
        final applied = await environment.call(
          'dartitect_apply_change',
          <String, Object?>{
            'planId': preview.structuredContent?['planId']! as String,
            'confirmed': true,
          },
        );
        expect(applied.structuredContent?['ok'], isTrue);
        expect(
          await source.readAsString(),
          contains('final class const User({'),
        );
      },
    );

    test('rejects expired and stale plans without writing', () async {
      var now = DateTime.utc(2026, 1, 1);
      var sequence = 0;
      final project = await _project(
        source: "import 'package:flutter/widgets.dart';\n",
        sourcePath: 'lib/features/example/domain/model.dart',
      );
      final environment = _Environment(
        DartitectMcpPolicy(
          allowedRoots: <Directory>[project],
          allowWrites: true,
          planTtl: const Duration(minutes: 10),
          now: () => now,
          createPlanId: () =>
              'deterministic-plan-${sequence++}'.padRight(24, '0'),
        ),
      );
      addTearDown(environment.close);
      await environment.initialize();

      final expiredPreview = await environment.call(
        'dartitect_preview_baseline',
      );
      now = now.add(const Duration(minutes: 11));
      final expired = await environment.call(
        'dartitect_apply_change',
        <String, Object?>{
          'planId': expiredPreview.structuredContent?['planId']! as String,
          'confirmed': true,
        },
      );
      expect(_errorCode(expired), 'plan_expired');

      final stalePreview = await environment.call('dartitect_preview_baseline');
      await File('${project.path}/lib/features/example/domain/model.dart')
          .writeAsString('BuildContext? context;\n');
      final stale = await environment.call(
        'dartitect_apply_change',
        <String, Object?>{
          'planId': stalePreview.structuredContent?['planId']! as String,
          'confirmed': true,
        },
      );
      expect(_errorCode(stale), 'stale_plan');
      expect(
        File('${project.path}/.dartitect/baseline.json').existsSync(),
        isFalse,
      );
    });

    test(
      'filesystem lock refuses a competing process without writing',
      () async {
        final project = await _project();
        final environment = _Environment(
          DartitectMcpPolicy(
            allowedRoots: <Directory>[project],
            allowWrites: true,
            createPlanId: () => 'locked-plan-identifier-0001',
          ),
        );
        addTearDown(environment.close);
        await environment.initialize();
        final preview = await environment.call('dartitect_preview_init');
        final lockDirectory = Directory('${project.path}/.dartitect');
        await lockDirectory.create();
        final lockPath = '${lockDirectory.path}/project-change.lock';
        final helper = File('${project.path}/hold_lock.dart');
        await helper.writeAsString(r'''
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final file = await File(arguments.single).open(mode: FileMode.append);
  await file.lock(FileLock.exclusive);
  stdout.writeln('locked');
  await stdin.first;
  await file.unlock();
  await file.close();
}
''');
        final holder = await Process.start(
          Platform.resolvedExecutable,
          <String>[helper.path, lockPath],
        );
        expect(
          await holder.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first
              .timeout(const Duration(seconds: 10)),
          'locked',
        );
        try {
          final result = await environment.call(
            'dartitect_apply_change',
            <String, Object?>{
              'planId': preview.structuredContent?['planId']! as String,
              'confirmed': true,
            },
          );
          expect(_errorCode(result), 'change_locked');
          expect(File('${project.path}/dartitect.json').existsSync(), isFalse);
        } finally {
          holder.stdin.writeln('release');
          await holder.stdin.close();
          expect(await holder.exitCode.timeout(const Duration(seconds: 10)), 0);
        }
      },
    );

    test(
      'read-only project filesystem fails closed without a partial change',
      () async {
        if (Platform.isWindows) return;
        final project = await _project();
        final environment = _Environment(
          DartitectMcpPolicy(
            allowedRoots: <Directory>[project],
            allowWrites: true,
            createPlanId: () => 'readonly-plan-identifier-01',
          ),
        );
        addTearDown(environment.close);
        await environment.initialize();
        final preview = await environment.call('dartitect_preview_init');
        final chmod = await Process.run('chmod', <String>[
          '0555',
          project.path,
        ]);
        expect(chmod.exitCode, 0);
        try {
          final result = await environment.call(
            'dartitect_apply_change',
            <String, Object?>{
              'planId': preview.structuredContent?['planId']! as String,
              'confirmed': true,
            },
          );
          expect(_errorCode(result), 'filesystem_error');
          expect(File('${project.path}/dartitect.json').existsSync(), isFalse);
        } finally {
          await Process.run('chmod', <String>['0755', project.path]);
        }
      },
    );

    test('parallel apply requests serialize per root', () async {
      final project = await _project();
      var sequence = 0;
      final environment = _Environment(
        DartitectMcpPolicy(
          allowedRoots: <Directory>[project],
          allowWrites: true,
          createPlanId: () => 'parallel-plan-${sequence++}'.padRight(24, '0'),
        ),
      );
      addTearDown(environment.close);
      await environment.initialize();
      final first = await environment.call('dartitect_preview_init');
      final second = await environment.call('dartitect_preview_init');

      final results = await Future.wait(<Future<CallToolResult>>[
        for (final preview in <CallToolResult>[first, second])
          environment.call('dartitect_apply_change', <String, Object?>{
            'planId': preview.structuredContent?['planId']! as String,
            'confirmed': true,
          }),
      ]);

      expect(results.where((result) => result.isError != true), hasLength(1));
      expect(
        results.where((result) => result.isError == true).map(_errorCode),
        everyElement(anyOf('concurrent_change', 'stale_plan')),
      );
      expect(File('${project.path}/dartitect.json').existsSync(), isTrue);
    });
  });
}

String? _errorCode(CallToolResult result) =>
    ((result.structuredContent?['error'] as Map<String, Object?>?)?['code'])
        as String?;

Future<Directory> _project({
  String source = 'void main() {}\n',
  String sourcePath = 'lib/main.dart',
}) async {
  final root = await Directory.systemTemp.createTemp('dartitect-mcp-test-');
  addTearDown(() async {
    for (var attempt = 0; await root.exists(); attempt++) {
      try {
        await root.delete(recursive: true);
      } on FileSystemException {
        // A Future.timeout does not cancel its underlying filesystem work.
        // Windows can retain that handle briefly after server shutdown.
        if (!Platform.isWindows || attempt == 19) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });
  await File('${root.path}/pubspec.yaml').writeAsString('''name: fixture
environment:
  sdk: ^3.13.0
''');
  final file = File('${root.path}/$sourcePath');
  await file.parent.create(recursive: true);
  await file.writeAsString(source);
  return root;
}

Future<Directory> _modelProject(String source) async {
  final root = await _project(source: source, sourcePath: 'lib/user.dart');
  await Directory('${root.path}/.dart_tool').create(recursive: true);
  await File('${root.path}/pubspec.yaml').writeAsString('''name: fixture
environment:
  sdk: ^3.13.0
dependencies:
  dartitect_modeling: any
''');
  final dartitect = await Isolate.resolvePackageUri(
    Uri.parse('package:dartitect/dartitect.dart'),
  );
  final modeling = await Isolate.resolvePackageUri(
    Uri.parse('package:dartitect_modeling/dartitect_modeling.dart'),
  );
  if (dartitect == null || modeling == null) {
    throw StateError('Modeling package graph is unresolved.');
  }
  await File('${root.path}/.dart_tool/package_config.json').writeAsString(
    jsonEncode(<String, Object?>{
      'configVersion': 2,
      'packages': <Object?>[
        <String, Object?>{
          'name': 'fixture',
          'rootUri': '../',
          'packageUri': 'lib/',
          'languageVersion': '3.13',
        },
        <String, Object?>{
          'name': 'dartitect',
          'rootUri': dartitect.resolve('../').toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.13',
        },
        <String, Object?>{
          'name': 'dartitect_modeling',
          'rootUri': modeling.resolve('../').toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.13',
        },
      ],
    }),
  );
  return root;
}

final class _Environment {
  _Environment(DartitectMcpPolicy policy) {
    server = DartitectMcpServer(
      StreamChannel<String>.withCloseGuarantee(
        clientToServer.stream,
        serverToClient.sink,
      ),
      policy: policy,
      diagnosticSink: diagnostics,
    );
    connection = client.connectServer(
      StreamChannel<String>.withCloseGuarantee(
        serverToClient.stream,
        clientToServer.sink,
      ),
    );
  }

  final clientToServer = StreamController<String>();
  final serverToClient = StreamController<String>();
  final diagnostics = StringBuffer();
  final client = MCPClient(
    Implementation(name: 'dartitect_mcp_test', version: '1.0.0'),
  );
  late final DartitectMcpServer server;
  late final ServerConnection connection;

  Future<InitializeResult> initialize() async {
    final result = await connection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    connection.notifyInitialized(InitializedNotification());
    await server.initialized;
    return result;
  }

  Future<CallToolResult> call(String name, [Map<String, Object?>? arguments]) =>
      connection.callTool(CallToolRequest(name: name, arguments: arguments));

  Future<void> close() async {
    await client.shutdown();
    await server.shutdown();
    if (!clientToServer.isClosed) await clientToServer.close();
    if (!serverToClient.isClosed) await serverToClient.close();
  }
}
