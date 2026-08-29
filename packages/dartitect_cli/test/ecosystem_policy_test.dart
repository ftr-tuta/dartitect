import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test('audit reports every direct owner and deterministic route', () async {
    final root = await _graphFixture(
      direct: const <String>['client_a', 'client_b'],
      edges: const <String, List<String>>{
        'client_a': <String>['provider'],
        'client_b': <String>['provider'],
        'provider': <String>[],
      },
    );
    addTearDown(() => root.delete(recursive: true));

    final report = await EcosystemDependencyAuditor(
      root,
      EcosystemPolicy.bundled,
    ).audit();
    final finding = report.findings.singleWhere(
      (finding) => finding.package == 'provider',
    );
    expect(finding.code, 'DT1017');
    expect(finding.severity, FindingSeverity.error);
    expect(finding.directOwners, <String>['client_a', 'client_b']);
    expect(finding.dependencyPaths, <String>[
      'client_a > provider',
      'client_b > provider',
    ]);
  });

  test(
    'installed architecture runtime and concrete leakage are errors',
    () async {
      final root = await _graphFixture(
        direct: const <String>['provider'],
        edges: const <String, List<String>>{'provider': <String>[]},
      );
      addTearDown(() => root.delete(recursive: true));
      final installed = await EcosystemDependencyAuditor(
        root,
        EcosystemPolicy.bundled,
      ).audit();
      expect(installed.findings.single.code, 'DT1017');
      expect(installed.findings.single.severity, FindingSeverity.error);

      final source = File('${root.path}/lib/domain/leak.dart');
      await source.parent.create(recursive: true);
      await source.writeAsString("import 'package:provider/provider.dart';\n");
      final scan = await DartitectProjectService(root).scanArchitecture();
      expect(scan.violations, isNotEmpty);
      expect(
        scan.violations.every(
          (finding) => finding.severity == FindingSeverity.error,
        ),
        isTrue,
      );
    },
  );

  test('overlay must cover every owner of a reviewed transitive', () async {
    final root = await _graphFixture(
      direct: const <String>['client_a', 'client_b'],
      edges: const <String, List<String>>{
        'client_a': <String>['pdf'],
        'client_b': <String>['pdf'],
        'pdf': <String>[],
      },
    );
    addTearDown(() => root.delete(recursive: true));
    final global = _policy(<String, Object?>{
      'client_a': _decision('approved'),
      'client_b': _decision('approved'),
      'pdf': _decision('reviewed_exception'),
    });
    final incomplete = EcosystemPolicy.withOverlay(
      global,
      _overlay(<String>['client_a']),
    );
    final blocked = await EcosystemDependencyAuditor(root, incomplete).audit();
    expect(
      blocked.findings
          .singleWhere((finding) => finding.package == 'pdf')
          .directOwners,
      <String>['client_a', 'client_b'],
    );

    final complete = EcosystemPolicy.withOverlay(
      global,
      _overlay(<String>['client_a', 'client_b']),
    );
    final accepted = await EcosystemDependencyAuditor(root, complete).audit();
    expect(accepted.findings, isEmpty);
  });

  test('consumer overlay cannot disable a universal prohibition', () {
    final global = _policy(<String, Object?>{
      'provider': _decision(
        'prohibited_native_strict',
        replacement: 'constructor injection',
      ),
    });
    final overlaid = EcosystemPolicy.withOverlay(global, <String, Object?>{
      'schemaVersion': 1,
      'entries': <Object?>[
        <String, Object?>{
          'package': 'provider',
          'decision': 'approved',
          'owner': 'application team',
          'reason': 'attempted architecture bypass',
          'expiresOn': '2026-11-22',
          'paths': <String>['lib/infrastructure/**'],
        },
      ],
    });

    expect(overlaid.validationFindings.single.code, 'DT1018');
    expect(
      overlaid.explain('provider').decision,
      EcosystemDecision.prohibitedNativeStrict,
    );
  });

  test(
    'advisory alternatives are informational until a conflict is active',
    () async {
      final advisoryRoot = await _graphFixture(
        direct: const <String>['sentry_dio'],
        edges: const <String, List<String>>{'sentry_dio': <String>[]},
      );
      addTearDown(() => advisoryRoot.delete(recursive: true));
      final policy = _policy(<String, Object?>{
        'sentry_dio': _decision(
          'advisory_alternative',
          replacement: 'one instrumentation path',
          conflictsWith: const <String>['dartitect_dio'],
        ),
      });
      expect(
        (await EcosystemDependencyAuditor(
          advisoryRoot,
          policy,
        ).audit()).findings,
        isEmpty,
      );

      final duplicateRoot = await _graphFixture(
        direct: const <String>['dartitect_dio', 'sentry_dio'],
        edges: const <String, List<String>>{
          'dartitect_dio': <String>[],
          'sentry_dio': <String>[],
        },
      );
      addTearDown(() => duplicateRoot.delete(recursive: true));
      final duplicate = await EcosystemDependencyAuditor(
        duplicateRoot,
        policy,
      ).audit();
      expect(duplicate.findings.single.package, 'sentry_dio');
      expect(duplicate.findings.single.code, 'DT1017');
    },
  );

  test(
    'unknown packages are advisory for consumers and block workspace audit',
    () async {
      final root = await _graphFixture(
        direct: const <String>['unknown_package'],
        edges: const <String, List<String>>{'unknown_package': <String>[]},
      );
      addTearDown(() => root.delete(recursive: true));
      final policy = _policy(const <String, Object?>{});

      expect(
        (await EcosystemDependencyAuditor(root, policy).audit()).findings,
        isEmpty,
      );
      final release = await EcosystemDependencyAuditor(
        root,
        policy,
        blockUnreviewed: true,
      ).audit();
      expect(release.findings.single.package, 'unknown_package');
      expect(release.findings.single.code, 'DT1018');
    },
  );

  test('invalid or global overlay scope is DT1018', () {
    final global = _policy(<String, Object?>{
      'pdf': _decision('reviewed_exception'),
    });
    final policy = EcosystemPolicy.withOverlay(global, <String, Object?>{
      'schemaVersion': 1,
      'entries': <Object?>[
        <String, Object?>{
          'package': 'pdf',
          'decision': 'approved',
          'owner': 'application team',
          'reason': 'too broad',
          'expiresOn': '2026-11-22',
          'paths': <String>['**/*'],
        },
      ],
    });

    expect(policy.validationFindings.single.code, 'DT1018');
    expect(policy.exceptionFor('pdf', DateTime.utc(2026, 8, 25)), isNull);
  });

  test(
    'expired, absolute, traversal, and platform-global scopes fail closed',
    () async {
      final global = _policy(<String, Object?>{
        'client': _decision('approved'),
        'pdf': _decision('reviewed_exception'),
      });
      for (final path in <String>[
        '*',
        '**',
        '**/*',
        '/lib/infrastructure/**',
        'lib/../outside/**',
        r'lib\infrastructure\**',
      ]) {
        final invalid = EcosystemPolicy.withOverlay(global, <String, Object?>{
          'schemaVersion': 1,
          'entries': <Object?>[
            <String, Object?>{
              'package': 'pdf',
              'decision': 'approved',
              'owner': 'application team',
              'reason': 'invalid scope fixture',
              'expiresOn': '2026-11-22',
              'paths': <String>[path],
              'directOwners': <String>['client'],
            },
          ],
        });
        expect(invalid.validationFindings.single.code, 'DT1018', reason: path);
      }

      final expired = EcosystemPolicy.withOverlay(global, <String, Object?>{
        'schemaVersion': 1,
        'entries': <Object?>[
          <String, Object?>{
            'package': 'pdf',
            'decision': 'approved',
            'owner': 'application team',
            'reason': 'expired fixture',
            'expiresOn': '2000-01-01',
            'paths': <String>['lib/infrastructure/documents/**'],
            'directOwners': <String>['client'],
          },
        ],
      });
      expect(
        expired.exceptionFor(
          'pdf',
          DateTime.utc(2026, 8, 25),
          directOwner: 'client',
        ),
        isNull,
      );
      final root = await _graphFixture(
        direct: const <String>['client'],
        edges: const <String, List<String>>{
          'client': <String>['pdf'],
          'pdf': <String>[],
        },
      );
      addTearDown(() => root.delete(recursive: true));
      final report = await EcosystemDependencyAuditor(root, expired).audit();
      expect(report.findings.single.package, 'pdf');
      expect(report.findings.single.code, 'DT1018');
    },
  );

  test('dependencies explain emits neutral advisory JSON', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-explain-');
    addTearDown(() => root.delete(recursive: true));
    final output = StringBuffer();
    final code = await DartitectCliRunner(
      currentDirectory: root,
      stdoutSink: output,
      stderrSink: StringBuffer(),
    ).run(<String>['dependencies', 'explain', 'uuid', '--json']);
    final decoded = jsonDecode(output.toString()) as Map<String, Object?>;

    expect(code, 0);
    expect(decoded['decision'], 'advisory_alternative');
    expect(decoded['replacement'], contains('SecureUuidV4Generator'));
  });

  test('policy dimensions keep listen approved but not adopted', () {
    final listen = EcosystemPolicy.bundled.explain('listen');

    expect(listen.decision, EcosystemDecision.approvedPrimitive);
    expect(listen.boundary, 'pure_dart_primitive');
    expect(listen.maturity, 'reviewed');
    expect(listen.adoptionStatus, 'deferred_until_real_consumer');
    expect(listen.compatibility, contains('nominal interoperability'));
    expect(listen.toJson(), containsPair('decision', 'approved_primitive'));
  });
}

Future<Directory> _graphFixture({
  required List<String> direct,
  required Map<String, List<String>> edges,
}) async {
  final root = await Directory.systemTemp.createTemp('dartitect-policy-');
  await File('${root.path}/pubspec.yaml').writeAsString('''
name: consumer
dependencies:
${direct.map((package) => '  $package: any').join('\n')}
''');
  await Directory('${root.path}/.dart_tool').create();
  await File('${root.path}/.dart_tool/package_graph.json').writeAsString(
    jsonEncode(<String, Object?>{
      'packages': <Object?>[
        <String, Object?>{
          'name': 'consumer',
          'dependencies': direct,
          'devDependencies': <String>[],
        },
        for (final entry in edges.entries)
          <String, Object?>{
            'name': entry.key,
            'dependencies': entry.value,
            'devDependencies': <String>[],
          },
      ],
    }),
  );
  return root;
}

EcosystemPolicy _policy(Map<String, Object?> decisions) =>
    EcosystemPolicy.fromJson(<String, Object?>{
      'schemaVersion': 3,
      'profile': 'native_strict',
      'documentation': 'policy.md',
      'decisions': decisions,
      'workspaceReviewedPackages': <String>[],
      'exceptions': <Object?>[],
    });

Map<String, Object?> _decision(
  String decision, {
  String? replacement,
  List<String> conflictsWith = const <String>[],
}) => <String, Object?>{
  'decision': decision,
  'owner': 'review authority',
  if (replacement != null) 'replacement': replacement,
  if (conflictsWith.isNotEmpty) 'conflictsWith': conflictsWith,
};

Map<String, Object?> _overlay(List<String> directOwners) => <String, Object?>{
  'schemaVersion': 1,
  'entries': <Object?>[
    <String, Object?>{
      'package': 'pdf',
      'decision': 'approved',
      'owner': 'application team',
      'reason': 'isolated document adapter',
      'expiresOn': '2026-11-22',
      'paths': <String>['lib/infrastructure/documents/**'],
      'directOwners': directOwners,
    },
  ],
};
