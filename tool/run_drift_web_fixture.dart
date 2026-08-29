import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _sqliteReleaseUri =
    'https://github.com/simolus3/drift/releases/download/'
    'drift-2.34.3/sqlite3.wasm';
const _sqliteSha256 =
    '41cf968998241465d8b1dfffb1eb60dd10c35de5022a3647e14174ea3af84143';
const _forbiddenWebDependencies = <String>[
  'objectbox',
  'objectbox_flutter_libs',
  'dartitect_objectbox',
];

Future<void> main() async {
  final root = Directory.current;
  final temporary = await Directory.systemTemp.createTemp(
    'dartitect-drift-web-',
  );
  try {
    final sqlite = File('${temporary.path}/sqlite3.wasm');
    await _downloadAndVerifySqlite(sqlite);
    final app = File('${temporary.path}/app.dart.js');
    final worker = File('${temporary.path}/drift_worker.dart.js');
    await _compile(root, 'tool/drift_web_fixture/app.dart', app);
    await _compile(root, 'tool/drift_web_fixture/worker.dart', worker);
    await _verifyDependencyGraph(temporary);

    for (final profile in const <_WebProfile>[
      _WebProfile(name: 'portable', isolated: false),
      _WebProfile(name: 'isolated', isolated: true),
    ]) {
      final diagnostics = <String>[];
      try {
        await _runProfile(
          profile: profile,
          temporary: temporary,
          sqlite: sqlite,
          app: app,
          worker: worker,
          diagnostics: diagnostics,
        );
      } catch (error, stackTrace) {
        for (final event in diagnostics) {
          stderr.writeln(event);
        }
        await _writeDiagnostics(profile, diagnostics, error, stackTrace);
        rethrow;
      }
    }
    stdout.writeln(
      'Task vertical Drift web canary passed: portable, isolated.',
    );
  } finally {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  }
}

Future<void> _downloadAndVerifySqlite(File target) async {
  final client = HttpClient();
  try {
    var uri = Uri.parse(_sqliteReleaseUri);
    HttpClientResponse response;
    for (var redirects = 0; ; redirects += 1) {
      if (redirects > 5) throw StateError('Too many sqlite3.wasm redirects.');
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      response = await request.close();
      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null)
          throw StateError('WASM redirect had no location.');
        uri = uri.resolve(location);
        continue;
      }
      break;
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw StateError(
        'sqlite3.wasm download returned ${response.statusCode}.',
      );
    }
    final sink = target.openWrite();
    try {
      await response.pipe(sink);
    } finally {
      await sink.close();
    }
    final digest = sha256.convert(await target.readAsBytes()).toString();
    if (digest != _sqliteSha256) {
      throw StateError('sqlite3.wasm SHA-256 did not match Drift 2.34.3.');
    }
  } finally {
    client.close(force: true);
  }
}

Future<void> _compile(Directory root, String source, File output) async {
  final result = await Process.run('dart', <String>[
    'compile',
    'js',
    '-O4',
    '-o',
    output.path,
    source,
  ], workingDirectory: root.path);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0 || !await output.exists()) {
    throw StateError('Dart web compilation failed for $source.');
  }
}

Future<void> _verifyDependencyGraph(Directory temporary) async {
  final dependencyFiles = temporary
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.deps'))
      .toList(growable: false);
  if (dependencyFiles.length < 2) {
    throw StateError('Dart web compilation did not emit dependency graphs.');
  }
  final graph = StringBuffer();
  for (final file in dependencyFiles) {
    graph.writeln(await file.readAsString());
  }
  for (final forbidden in _forbiddenWebDependencies) {
    if (graph.toString().contains(forbidden)) {
      throw StateError('Web dependency graph contains $forbidden.');
    }
  }
}

Future<void> _runProfile({
  required _WebProfile profile,
  required Directory temporary,
  required File sqlite,
  required File app,
  required File worker,
  required List<String> diagnostics,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final serverTask = _serve(
    server,
    profile: profile,
    sqlite: sqlite,
    app: app,
    worker: worker,
  );
  Process? chrome;
  _CdpClient? cdp;
  final profileDirectory = await Directory(
    '${temporary.path}/chrome-${profile.name}',
  ).create();
  try {
    await _verifyWasmMime(server.port, profile);
    final executable = await _findChrome();
    chrome = await Process.start(executable, <String>[
      '--headless=new',
      '--no-sandbox',
      '--disable-gpu',
      '--disable-dev-shm-usage',
      '--remote-debugging-address=127.0.0.1',
      '--remote-debugging-port=0',
      '--user-data-dir=${profileDirectory.path}',
      'about:blank',
    ]);
    _captureProcessOutput(chrome, diagnostics);
    final websocket = await _waitForDevTools(profileDirectory, chrome);
    cdp = await _CdpClient.connect(websocket, diagnostics);

    final databaseName = 'dartitect-${profile.name}-rc8';
    final primary = await _openPage(
      cdp,
      server.port,
      role: 'primary',
      databaseName: databaseName,
    );
    final primaryReady = await _waitForStatus(cdp, primary, 'READY:');
    _requireSafeStatus(primaryReady);

    final secondary = await _openPage(
      cdp,
      server.port,
      role: 'secondary',
      databaseName: databaseName,
    );
    await cdp.call('Page.bringToFront', sessionId: secondary.sessionId);
    final secondaryReady = await _waitForStatus(cdp, secondary, 'READY:');
    _requireSafeStatus(secondaryReady);

    await cdp.call('Page.bringToFront', sessionId: primary.sessionId);
    await _evaluate(
      cdp,
      primary,
      'localStorage.setItem('
      '"dartitect-primary-foreground", ${jsonEncode(databaseName)})',
    );
    final primaryPassed = await _waitForStatus(cdp, primary, 'PASS:');
    final secondaryPassed = await _waitForStatus(cdp, secondary, 'PASS:');
    _requireSafeStatus(primaryPassed);
    _requireSafeStatus(secondaryPassed);
    if (!primaryPassed.endsWith(':foreground') ||
        !secondaryPassed.endsWith(':cross-context-watch')) {
      throw StateError('Web foreground or multi-context evidence is missing.');
    }

    final isolated = await _evaluate(cdp, primary, 'crossOriginIsolated');
    if (isolated != profile.isolated) {
      throw StateError('${profile.name} cross-origin isolation mismatch.');
    }

    await cdp.call(
      'Target.closeTarget',
      params: <String, Object?>{'targetId': secondary.targetId},
    );
    await cdp.call(
      'Target.closeTarget',
      params: <String, Object?>{'targetId': primary.targetId},
    );
  } finally {
    await cdp?.close();
    await _terminate(chrome);
    await server.close(force: true);
    await serverTask;
  }
}

Future<void> _serve(
  HttpServer server, {
  required _WebProfile profile,
  required File sqlite,
  required File app,
  required File worker,
}) async {
  await for (final request in server) {
    if (profile.isolated) {
      request.response.headers
        ..set('Cross-Origin-Opener-Policy', 'same-origin')
        ..set('Cross-Origin-Embedder-Policy', 'require-corp');
    }
    request.response.headers.set('Cache-Control', 'no-store');
    switch (request.uri.path) {
      case '/':
        request.response.headers.contentType = ContentType.html;
        request.response.write('''<!doctype html>
<html><head><meta charset="utf-8"><title>Drift fixture</title></head>
<body>BOOTING<script defer src="/app.dart.js"></script></body></html>''');
      case '/app.dart.js':
        request.response.headers.contentType = ContentType(
          'text',
          'javascript',
          charset: 'utf-8',
        );
        await request.response.addStream(app.openRead());
      case '/drift_worker.dart.js':
        request.response.headers.contentType = ContentType(
          'text',
          'javascript',
          charset: 'utf-8',
        );
        await request.response.addStream(worker.openRead());
      case '/sqlite3.wasm':
        request.response.headers.contentType = ContentType(
          'application',
          'wasm',
        );
        await request.response.addStream(sqlite.openRead());
      default:
        request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  }
}

Future<void> _verifyWasmMime(int port, _WebProfile profile) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port/sqlite3.wasm'),
    );
    final response = await request.close();
    final mime = response.headers.contentType?.mimeType;
    await response.drain<void>();
    if (response.statusCode != HttpStatus.ok || mime != 'application/wasm') {
      throw StateError('WASM MIME validation failed for ${profile.name}.');
    }
    final coop = response.headers.value('Cross-Origin-Opener-Policy');
    final coep = response.headers.value('Cross-Origin-Embedder-Policy');
    if (profile.isolated) {
      if (coop != 'same-origin' || coep != 'require-corp') {
        throw StateError('Isolated profile headers are missing.');
      }
    } else if (coop != null || coep != null) {
      throw StateError('Portable profile unexpectedly enabled isolation.');
    }
  } finally {
    client.close(force: true);
  }
}

Future<String> _findChrome() async {
  for (final executable in const <String>[
    'google-chrome',
    'google-chrome-stable',
    'chromium',
    'chromium-browser',
  ]) {
    try {
      final result = await Process.run(executable, const <String>['--version']);
      if (result.exitCode == 0) return executable;
    } on ProcessException {
      continue;
    }
  }
  throw StateError('A real Chrome or Chromium executable is required.');
}

Future<Uri> _waitForDevTools(Directory profile, Process chrome) async {
  final activePort = File('${profile.path}/DevToolsActivePort');
  for (var attempt = 0; attempt < 300; attempt += 1) {
    if (await activePort.exists()) {
      final lines = await activePort.readAsLines();
      if (lines.length >= 2) {
        return Uri.parse('ws://127.0.0.1:${lines[0]}${lines[1]}');
      }
    }
    final exited = await chrome.exitCode.timeout(
      Duration.zero,
      onTimeout: () => -1,
    );
    if (exited != -1) throw StateError('Chrome exited before CDP was ready.');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('Chrome DevTools endpoint did not become ready.');
}

void _captureProcessOutput(Process process, List<String> diagnostics) {
  process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => _retain(diagnostics, 'chrome-out:$line'));
  process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => _retain(diagnostics, 'chrome-err:$line'));
}

Future<_CdpPage> _openPage(
  _CdpClient cdp,
  int port, {
  required String role,
  required String databaseName,
}) async {
  final target = await cdp.call(
    'Target.createTarget',
    params: <String, Object?>{'url': 'about:blank'},
  );
  final targetId = target['targetId']! as String;
  final attached = await cdp.call(
    'Target.attachToTarget',
    params: <String, Object?>{'targetId': targetId, 'flatten': true},
  );
  final sessionId = attached['sessionId']! as String;
  await cdp.call('Page.enable', sessionId: sessionId);
  await cdp.call('Runtime.enable', sessionId: sessionId);
  final uri = Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: port,
    path: '/',
    queryParameters: <String, String>{'role': role, 'database': databaseName},
  );
  await cdp.call(
    'Page.navigate',
    sessionId: sessionId,
    params: <String, Object?>{'url': uri.toString()},
  );
  await _waitForExpression(
    cdp,
    _CdpPage(targetId, sessionId),
    'document.readyState === "complete"',
  );
  return _CdpPage(targetId, sessionId);
}

Future<void> _waitForExpression(
  _CdpClient cdp,
  _CdpPage page,
  String expression,
) async {
  for (var attempt = 0; attempt < 300; attempt += 1) {
    if (await _evaluate(cdp, page, expression) == true) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('CDP expression did not become true.');
}

Future<String> _waitForStatus(
  _CdpClient cdp,
  _CdpPage page,
  String prefix,
) async {
  for (var attempt = 0; attempt < 600; attempt += 1) {
    final value = await _evaluate(cdp, page, 'document.body.textContent');
    if (value is String) {
      if (value.startsWith('FAIL:')) throw StateError(value);
      if (value.startsWith(prefix)) return value;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('CDP page did not report $prefix.');
}

Future<Object?> _evaluate(
  _CdpClient cdp,
  _CdpPage page,
  String expression,
) async {
  final response = await cdp.call(
    'Runtime.evaluate',
    sessionId: page.sessionId,
    params: <String, Object?>{
      'expression': expression,
      'returnByValue': true,
      'awaitPromise': true,
    },
  );
  final remote = response['result']! as Map<String, Object?>;
  return remote['value'];
}

void _requireSafeStatus(String status) {
  if (status.contains('unsafeIndexedDb') || status.contains('inMemory')) {
    throw StateError('Drift Web selected unsafe storage: $status');
  }
}

Future<void> _terminate(Process? process) async {
  if (process == null) return;
  process.kill(ProcessSignal.sigterm);
  final exit = process.exitCode;
  try {
    await exit.timeout(const Duration(seconds: 3));
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await exit;
  }
}

Future<void> _writeDiagnostics(
  _WebProfile profile,
  List<String> diagnostics,
  Object error,
  StackTrace stackTrace,
) async {
  final path = Platform.environment['DARTITECT_DRIFT_WEB_DIAGNOSTICS'];
  if (path == null || path.isEmpty) return;
  final directory = await Directory(path).create(recursive: true);
  await File('${directory.path}/${profile.name}.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'profile': profile.name,
      'errorType': error.runtimeType.toString(),
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
      'events': diagnostics,
    }),
  );
}

void _retain(List<String> diagnostics, String line) {
  if (diagnostics.length == 500) diagnostics.removeAt(0);
  diagnostics.add(line.length <= 2000 ? line : line.substring(0, 2000));
}

final class _CdpClient {
  _CdpClient._(this._socket, this._diagnostics) {
    _subscription = _socket.listen(
      _onMessage,
      onError: (Object error, StackTrace stackTrace) {
        for (final pending in _pending.values) {
          if (!pending.isCompleted) pending.completeError(error, stackTrace);
        }
        _pending.clear();
      },
    );
  }

  final WebSocket _socket;
  final List<String> _diagnostics;
  final Map<int, Completer<Map<String, Object?>>> _pending =
      <int, Completer<Map<String, Object?>>>{};
  late final StreamSubscription<dynamic> _subscription;
  var _nextId = 0;

  static Future<_CdpClient> connect(Uri uri, List<String> diagnostics) async =>
      _CdpClient._(await WebSocket.connect(uri.toString()), diagnostics);

  Future<Map<String, Object?>> call(
    String method, {
    String? sessionId,
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    final id = ++_nextId;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _socket.add(
      jsonEncode(<String, Object?>{
        'id': id,
        'method': method,
        'params': params,
        if (sessionId != null) 'sessionId': sessionId,
      }),
    );
    return completer.future.timeout(const Duration(seconds: 30));
  }

  void _onMessage(dynamic data) {
    final message = jsonDecode(data as String) as Map<String, Object?>;
    final id = message['id'];
    if (id is int) {
      final completer = _pending.remove(id);
      if (completer == null) return;
      final error = message['error'];
      if (error != null) {
        completer.completeError(StateError('CDP error: $error'));
      } else {
        completer.complete(
          (message['result'] as Map<Object?, Object?>?)
                  ?.cast<String, Object?>() ??
              <String, Object?>{},
        );
      }
      return;
    }
    final method = message['method'];
    if (method == 'Runtime.consoleAPICalled' ||
        method == 'Runtime.exceptionThrown') {
      _retain(_diagnostics, 'cdp:${jsonEncode(message)}');
    }
  }

  Future<void> close() async {
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('CDP client closed.'));
      }
    }
    _pending.clear();
    await _subscription.cancel();
    await _socket.close();
  }
}

final class _CdpPage {
  const _CdpPage(this.targetId, this.sessionId);

  final String targetId;
  final String sessionId;
}

final class _WebProfile {
  const _WebProfile({required this.name, required this.isolated});

  final String name;
  final bool isolated;
}
