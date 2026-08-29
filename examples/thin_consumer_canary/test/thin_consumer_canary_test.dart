import 'dart:convert';
import 'dart:io';

import 'package:dartitect/dartitect_credentials.dart';
import 'package:dartitect_flutter/dartitect_flutter_forms.dart';
import 'package:dartitect_flutter/dartitect_flutter_queries.dart';
import 'package:dartitect_transfer/dartitect_attachments.dart';
import 'package:dartitect_workmanager/dartitect_workmanager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thin_consumer_canary/features/tasks/composition/tasks.wiring.dartitect.g.dart';

final class _Failure implements Exception {
  const _Failure();
}

void main() {
  test('strict wiring enables the complete opt-in workflow set', () async {
    expect(TasksFeatureWiring.profile, 'offline-full');
    expect(TasksFeatureWiring.scope, 'application');
    expect(TasksFeatureWiring.storageContext, 'primary');
    expect(TasksFeatureWiring.transport, 'api');
    expect(TasksFeatureWiring.scheduler, 'workmanager');
    expect(TasksFeatureWiring.headlessTargets, <String>[
      'android',
      'ios',
      'macos',
      'linux',
      'web',
    ]);
    expect(TasksFeatureWiring.capabilities, <String>[
      'attachments',
      'credentials',
      'forms',
      'queries',
    ]);

    const credential = CredentialRecord<String>(value: 'redacted');
    expect(credential.expiresAt, isNull);
    final attachment = AttachmentBackgroundRequest(
      protocolVersion: 1,
      attachmentId: 'attachment-1',
      deadline: DateTime.utc(2030),
    );
    expect(attachment.attachmentId, 'attachment-1');

    final form = DartitectFormController<int, _Failure>(
      original: 1,
      equals: (left, right) => left == right,
      submitter: (_, _) async => const Ok<void>(null),
    );
    form.update(2);
    expect(form.snapshot.dirty, isTrue);
    await form.disposeAsync();

    final page = DartitectQueryPage<int>(items: <int>[1], nextCursor: 'next');
    expect(page.items, <int>[1]);
    expect(page.nextCursor, 'next');

    final windows = DartitectWorkmanagerCapability.forPlatform(
      DartitectWorkmanagerPlatform.windows,
    );
    expect(windows.maturity, DartitectWorkmanagerMaturity.unsupported);
  });

  test('generated main stays on the public paved road', () {
    final lines = File('${_packageRoot().path}/lib/main.dart')
        .readAsLinesSync()
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    expect(lines, hasLength(lessThanOrEqualTo(15)));
    expect(lines.join('\n'), contains('runDartitectApplication'));
  });
}

Directory _packageRoot() {
  var directory = Directory.current.absolute;
  while (true) {
    final config = File('${directory.path}/.dart_tool/package_config.json');
    if (config.existsSync()) {
      final json =
          jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
      final packages = json['packages']! as List<Object?>;
      final entry = packages.cast<Map<String, Object?>>().singleWhere(
        (candidate) => candidate['name'] == 'thin_consumer_canary',
      );
      return Directory.fromUri(config.uri.resolve(entry['rootUri']! as String));
    }
    if (directory.parent.path == directory.path) {
      throw StateError('Dart package configuration was not found.');
    }
    directory = directory.parent;
  }
}
