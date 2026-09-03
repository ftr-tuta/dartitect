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
    final value = jsonDecode(
      File('${root.path}/tool/stable_candidate_contract.json')
          .readAsStringSync(),
    );
    final promotionBlockers = value is Map<String, Object?>
        ? _strings(value['promotionBlockers'])
        : const <String>[];
    if (value is! Map<String, Object?> ||
        value['schemaVersion'] != 4 ||
        value['goal'] != 'V1-18' ||
        value['authority'] != 'github-actions' ||
        value['stableVersion'] != '1.0.0' ||
        value['requiresExactMainSha'] != true ||
        value['requiresReadinessArtifact'] != 'actions-readiness-v1' ||
        value['requiresUiQualityEvidence'] != 'ui-quality-v2' ||
        value['requiresDeterministicActionsEvidence'] != 'CI / Required' ||
        value['requiresDistributionPolicy'] !=
            'tool/distribution_policy.json' ||
        value['requiredCheck'] != 'CI / Required' ||
        !_same(_strings(value['requiredNativeCells']), _nativeCells) ||
        value['releaseWorkflow'] != '.github/workflows/release.yaml' ||
        value['manualTriggerOnly'] != true ||
        promotionBlockers.isNotEmpty ||
        value['externalAuthorizationRecordsAccepted'] != false) {
      throw StateError('Stable Actions policy is incomplete.');
    }
    final uiQuality = await Process.run(Platform.resolvedExecutable, <String>[
      '${root.path}/tool/check_ui_quality.dart',
      '--root=${root.path}',
    ], workingDirectory: root.path);
    if (uiQuality.exitCode != 0) {
      throw StateError(
        'Stable candidate rejected ui-quality-v2: ${uiQuality.stderr}',
      );
    }
    final distribution = await Process.run(
      Platform.resolvedExecutable,
      <String>[
        '${root.path}/tool/check_distribution_policy.dart',
        '--root',
        root.path,
      ],
      workingDirectory: root.path,
    );
    if (distribution.exitCode != 0) {
      throw StateError(
        'Stable candidate rejected distribution policy: '
        '${distribution.stderr}',
      );
    }
    if (options.manifest != null) {
      final result = await Process.run(Platform.resolvedExecutable, <String>[
        '${root.path}/tool/check_actions_readiness.dart',
        '--root=${root.path}',
        '--manifest=${options.manifest!.path}',
      ], workingDirectory: root.path);
      if (result.exitCode != 0) {
        throw StateError(
          'Stable candidate rejected readiness: ${result.stderr}',
        );
      }
    }
    stdout.writeln(
      options.manifest == null
          ? 'Stable policy passed structurally with the nominal five-cell '
                'Actions matrix and ui-quality-v2 evidence; formal Actions '
                'readiness remains external.'
          : 'Stable candidate passed actions-readiness-v1 and ui-quality-v2.',
    );
  } on Object catch (error) {
    stderr.writeln('Stable candidate validation failed: $error');
    exitCode = error is FormatException ? 64 : 1;
  }
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
