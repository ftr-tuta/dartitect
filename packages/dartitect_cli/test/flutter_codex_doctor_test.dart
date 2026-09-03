import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:dartitect_cli/src/codex/flutter_codex_doctor.dart';
import 'package:dartitect_cli/src/codex/skill_catalog.dart';
import 'package:test/test.dart';

void main() {
  test('proves structured plugin, official skills, and managed hashes', () async {
    final root = await _root();
    await CodexSkillSynchronizer(root).sync();
    final config = File('${root.path}/.codex/config.toml');
    await config.parent.create();
    await config.writeAsString('[mcp_servers.flutter]\ncommand = "dart"\n');
    final doctor = FlutterCodexDoctor(
      root,
      environment: const <String, String>{},
      commandRunner: (executable, arguments) async {
        if (executable == 'codex' && arguments.contains('--json')) {
          return FlutterCodexCommandResult(
            exitCode: 0,
            stdout: jsonEncode(<String, Object?>{
              'installed': <Object?>[
                <String, Object?>{
                  'name': 'dart-flutter',
                  'selector': 'dart-flutter@dart-flutter',
                  'skills': officialFlutterQualitySkills,
                },
              ],
            }),
          );
        }
        return const FlutterCodexCommandResult(
          exitCode: 0,
          stdout: 'dart mcp-server',
        );
      },
    );

    final report = await doctor.inspect();

    expect(report.overallStatus, FlutterCodexCheckStatus.pass);
    expect(report.exitCode, 0);
    expect(report.toJson()['schemaVersion'], 1);
    expect(report.toJson()['command'], 'codex doctor --flutter');
    expect(
      report.checks
          .singleWhere((check) => check.id == 'dartitectSkills')
          .evidence,
      contains(
        '${dartitectSkillCatalog.length}/${dartitectSkillCatalog.length} managed Dartitect skills match manifests and hashes.',
      ),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('legacy fallback accepts only an exact plugin line', () async {
    final root = await _root();
    final report = await FlutterCodexDoctor(
      root,
      environment: const <String, String>{},
      commandRunner: (executable, arguments) async {
        if (executable == 'codex' && arguments.contains('--json')) {
          return const FlutterCodexCommandResult(exitCode: 2);
        }
        if (executable == 'codex' && arguments.contains('list')) {
          return const FlutterCodexCommandResult(
            exitCode: 0,
            stdout: 'installed: dart-flutter@dart-flutter extra\n',
          );
        }
        return const FlutterCodexCommandResult(
          exitCode: 0,
          stdout: 'dart mcp-server',
        );
      },
    ).inspect();

    final plugin = report.checks.singleWhere(
      (check) => check.id == 'officialPlugin',
    );
    expect(plugin.status, FlutterCodexCheckStatus.warning);
    expect(plugin.evidence.join(' '), contains('did not prove'));
  });

  test(
    'invalid transaction and config fail without modifying editor config',
    () async {
      final root = await _root();
      final journal = File('${root.path}/.dartitect-codex-sync.json');
      final backup = Directory('${root.path}/.dartitect-codex-backup');
      await journal.writeAsString('{invalid');
      await backup.create();
      final codexConfig = File('${root.path}/.codex/config.toml');
      await codexConfig.parent.create();
      await codexConfig.writeAsString('not toml');
      final editor = File('${root.path}/.vscode/mcp.json');
      await editor.parent.create();
      await editor.writeAsString('{"external":true}\n');

      final report = await FlutterCodexDoctor(
        root,
        environment: const <String, String>{},
        commandRunner: (_, __) async => const FlutterCodexCommandResult(
          exitCode: 0,
          stdout: '{"installed":[]}',
        ),
      ).inspect();

      expect(report.overallStatus, FlutterCodexCheckStatus.fail);
      expect(report.exitCode, 1);
      expect(
        report.checks
            .singleWhere((check) => check.id == 'transactionJournal')
            .status,
        FlutterCodexCheckStatus.fail,
      );
      expect(await editor.readAsString(), '{"external":true}\n');
    },
  );
}

Future<Directory> _root() async {
  final root = await Directory.systemTemp.createTemp('flutter-codex-doctor-');
  addTearDown(() => root.delete(recursive: true));
  return root;
}
