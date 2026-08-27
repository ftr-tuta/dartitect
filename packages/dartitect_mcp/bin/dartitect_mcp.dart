import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/stdio.dart';
import 'package:dartitect_mcp/dartitect_mcp.dart';

/// Starts the local STDIO Dartitect MCP server.
Future<void> main(List<String> arguments) async {
  final roots = <Directory>[];
  var allowWrites = false;
  for (var index = 0; index < arguments.length; index += 1) {
    final argument = arguments[index];
    if (argument == '--allow-writes') {
      allowWrites = true;
    } else if (argument == '--root') {
      if (index + 1 >= arguments.length) {
        stderr.writeln('--root requires a path.');
        exitCode = 64;
        return;
      }
      roots.add(Directory(arguments[++index]));
    } else if (argument.startsWith('--root=')) {
      roots.add(Directory(argument.substring('--root='.length)));
    } else if (argument == '--help' || argument == '-h') {
      stderr.writeln(_help);
      return;
    } else {
      stderr.writeln('Dartitect MCP received an unknown option.');
      exitCode = 64;
      return;
    }
  }
  roots.addIfEmpty(Directory.current);
  try {
    final server = DartitectMcpServer(
      stdioChannel(input: stdin, output: stdout),
      policy: DartitectMcpPolicy(allowedRoots: roots, allowWrites: allowWrites),
    );
    await server.done;
  } on Object {
    stderr.writeln(
      'Dartitect MCP failed to start. Check configured roots and options.',
    );
    exitCode = 70;
  }
}

const String _help = '''Dartitect MCP 1.0.0-rc.2

Usage: dart run dartitect_mcp:dartitect_mcp [--root PATH] [--allow-writes]

Transport: local STDIO only. Read-only by default.
Repeat --root to authorize more than one existing directory.''';

extension<T> on List<T> {
  void addIfEmpty(T value) {
    if (isEmpty) add(value);
  }
}
