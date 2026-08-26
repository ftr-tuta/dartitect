import 'dart:io';

import 'package:dart_mcp/stdio.dart';
import 'package:dartitect_mcp/dartitect_mcp.dart';

/// Runs a read-only server for the current project.
Future<void> main() async {
  final server = DartitectMcpServer(
    stdioChannel(input: stdin, output: stdout),
    policy: DartitectMcpPolicy(allowedRoots: <Directory>[Directory.current]),
  );
  await server.done;
}
