import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:test/test.dart';

void main() {
  test('real dart_mcp client completes the STDIO lifecycle', () async {
    final project = await Directory.systemTemp.createTemp(
      'dartitect-mcp-stdio-',
    );
    await File('${project.path}/pubspec.yaml').writeAsString('''name: fixture
environment:
  sdk: ^3.13.0
''');
    await Directory('${project.path}/lib').create();
    await File('${project.path}/lib/main.dart')
        .writeAsString('void main() {}\n');
    final process = await Process.start('dart', <String>[
      'run',
      'dartitect_mcp:dartitect_mcp',
      '--root',
      project.path,
    ], workingDirectory: Directory.current.path);
    final stderrText = StringBuffer();
    final stderrSubscription = process.stderr
        .transform(const SystemEncoding().decoder)
        .listen(stderrText.write);
    final client = MCPClient(
      Implementation(name: 'stdio_e2e_test', version: '1.0.0'),
    );
    final connection = client.connectServer(
      stdioChannel(input: process.stdout, output: process.stdin),
    );
    addTearDown(() async {
      await client.shutdown();
      process.kill();
      await stderrSubscription.cancel();
      if (await project.exists()) await project.delete(recursive: true);
    });

    final initialized = await connection
        .initialize(
          InitializeRequest(
            protocolVersion: ProtocolVersion.latestSupported,
            capabilities: client.capabilities,
            clientInfo: client.implementation,
          ),
        )
        .timeout(const Duration(seconds: 20));
    expect(initialized.instructions, contains('single-use'));
    connection.notifyInitialized(InitializedNotification());
    final tools = await connection.listTools();
    expect(tools.tools, hasLength(15));
    final inspect = await connection.callTool(
      CallToolRequest(name: 'dartitect_inspect_project'),
    );
    expect(inspect.structuredContent?['ok'], isTrue);

    await client.shutdown();
    final exit = await process.exitCode.timeout(const Duration(seconds: 10));
    expect(exit, 0, reason: stderrText.toString());
  });

  test(
    'startup failures keep stdout empty and redact configured paths',
    () async {
      final missing =
          '${Directory.systemTemp.path}/dartitect-missing-secret-root';
      final result = await Process.run('dart', <String>[
        'run',
        'dartitect_mcp:dartitect_mcp',
        '--root',
        missing,
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 70);
      expect(result.stdout, isEmpty);
      expect('${result.stderr}', isNot(contains(missing)));
      expect('${result.stderr}', contains('failed to start'));
    },
  );
}
