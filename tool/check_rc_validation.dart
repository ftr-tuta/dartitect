import 'dart:convert';
import 'dart:io';

const _nativeCells = <String>[
  'android-media-floor-build',
  'android-media-current-emulator',
  'ios-media-floor-build',
  'ios-privacy-floor-build',
  'ios-current-simulator',
];

Future<void> main(List<String> arguments) async {
  try {
    final options = _Options.parse(arguments);
    final root = options.root ?? File.fromUri(Platform.script).parent.parent;
    final contract = _object(
      jsonDecode(
        File('${root.path}/tool/rc_validation_contract.json')
            .readAsStringSync(),
      ),
    );
    final errors = <String>[];
    if (contract['schemaVersion'] != 2 ||
        contract['goal'] != 'V1S-17' ||
        contract['authority'] != 'github-actions' ||
        contract['toolingState'] != 'ACTIONS_POLICY_READY' ||
        contract['readinessArtifact'] != 'actions-readiness-v1' ||
        contract['requiredCheck'] != 'CI / Required' ||
        !_same(_strings(contract['requiredCanaries']), const <String>[
          'minimal',
          'offline_first',
          'native_capabilities',
        ]) ||
        !_same(_strings(contract['requiredNativeCells']), _nativeCells) ||
        contract['requiredResidualCensus'] != 0 ||
        !_same(_strings(contract['hostedRuntimeKinds']), const <String>[
          'emulator',
          'simulator',
        ]) ||
        contract['externalArtifactsAccepted'] != false) {
      errors.add('The Actions RC validation policy is incomplete.');
    }
    if (options.manifest != null && errors.isEmpty) {
      final result = await Process.run(Platform.resolvedExecutable, <String>[
        '${root.path}/tool/check_actions_readiness.dart',
        '--root=${root.path}',
        '--manifest=${options.manifest!.path}',
      ], workingDirectory: root.path);
      if (result.exitCode != 0) {
        errors.add(
          'RC validation rejected Actions readiness: ${result.stderr}',
        );
      }
    }
    if (errors.isNotEmpty) {
      stderr.writeln(errors.join('\n'));
      exitCode = 1;
      return;
    }
    stdout.writeln(
      options.manifest == null
          ? 'RC validation policy passed with the nominal five hosted native cells.'
          : 'RC validation passed from actions-readiness-v1.',
    );
  } on Object catch (error) {
    stderr.writeln('RC validation failed: $error');
    exitCode = error is FormatException ? 64 : 1;
  }
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

List<String> _strings(Object? value) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw const FormatException('Expected a JSON string list.');
  }
  return value.cast<String>();
}

bool _same(List<String> left, List<String> right) =>
    left.length == right.length &&
    left.asMap().entries.every((entry) => entry.value == right[entry.key]);

final class _Options {
  const _Options({this.root, this.manifest});

  factory _Options.parse(List<String> arguments) {
    Directory? root;
    File? manifest;
    for (final argument in arguments) {
      if (argument == '--contract-only') {
        continue;
      } else if (argument.startsWith('--root=')) {
        if (root != null) throw const FormatException('Duplicate root.');
        root = Directory(argument.substring('--root='.length)).absolute;
      } else if (argument.startsWith('--manifest=')) {
        if (manifest != null)
          throw const FormatException('Duplicate manifest.');
        manifest = File(argument.substring('--manifest='.length)).absolute;
      } else {
        throw FormatException('Unknown argument: $argument');
      }
    }
    return _Options(root: root, manifest: manifest);
  }

  final Directory? root;
  final File? manifest;
}
