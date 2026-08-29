import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test(
    'sync is deterministic and check observes generated freshness',
    () async {
      final root = await Directory.systemTemp.createTemp('dartitect-openapi-');
      addTearDown(() => root.delete(recursive: true));
      await _writeJson(root, 'contracts/api.json', _contract());
      final service = OpenApiContractService(root);

      final preview = await service.preview(specPath: 'contracts/api.json');
      expect(preview.isValid, isTrue);
      expect(preview.isFresh, isFalse);
      expect(preview.plan!.creates, hasLength(1));

      final applied = await service.apply(specPath: 'contracts/api.json');
      expect(applied.applied, isTrue);
      expect(applied.writes, 1);
      final output = File(
        '${root.path}/lib/contracts/api.contracts.dartitect.g.dart',
      );
      final first = await output.readAsString();
      expect(first, contains('final class const TaskDto'));
      expect(first, contains('Future<Response<Object?>> getTask'));
      expect(first, contains('Uri.encodeComponent'));
      expect(first, isNot(contains('Authorization')));
      expect(first, isNot(contains('Domain')));
      expect(first, isNot(contains('Mapper')));

      final checked = await service.inspect(specPath: 'contracts/api.json');
      expect(checked.isFresh, isTrue);
      expect((await service.apply(specPath: 'contracts/api.json')).writes, 0);
      expect(await output.readAsString(), first);
    },
  );

  test('comparison separates additive and breaking schema changes', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-openapi-');
    addTearDown(() => root.delete(recursive: true));
    await _writeJson(root, 'baseline.json', _contract());
    await _writeJson(root, 'additive.json', _contract(extraProperty: true));
    await _writeJson(
      root,
      'breaking.json',
      _contract(extraProperty: true, requireExtraProperty: true),
    );
    final service = OpenApiContractService(root);

    final additive = await service.inspect(
      specPath: 'additive.json',
      baselinePath: 'baseline.json',
    );
    expect(additive.isCompatible, isTrue);
    expect(
      additive.findings.map((finding) => finding.kind),
      contains(OpenApiContractFindingKind.additive),
    );

    final breaking = await service.inspect(
      specPath: 'breaking.json',
      baselinePath: 'baseline.json',
    );
    expect(breaking.isCompatible, isFalse);
    expect(
      breaking.findings.map((finding) => finding.kind),
      contains(OpenApiContractFindingKind.breaking),
    );
    expect(
      breaking.findings.map((finding) => finding.message),
      contains('Required property was added.'),
    );
  });

  test('remote refs and non-JSON pipelines are rejected without IO', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-openapi-');
    addTearDown(() => root.delete(recursive: true));
    final contract = _contract();
    final schemas =
        ((contract['components']! as Map<String, Object?>)['schemas']!
            as Map<String, Object?>);
    schemas['Remote'] = <String, Object?>{
      r'$ref': 'https://example.invalid/schema.json',
    };
    final operation =
        (((contract['paths']! as Map<String, Object?>)['/tasks/{id}']!
                as Map<String, Object?>)['get']!
            as Map<String, Object?>);
    operation['requestBody'] = <String, Object?>{
      'content': <String, Object?>{
        'multipart/form-data': <String, Object?>{
          'schema': <String, Object?>{'type': 'object'},
        },
      },
    };
    await _writeJson(root, 'invalid.json', contract);

    final report = await OpenApiContractService(root)
        .inspect(specPath: 'invalid.json');

    expect(report.isValid, isFalse);
    expect(report.plan, isNull);
    expect(
      report.findings.map((finding) => finding.code),
      containsAll(<String>['DT3102', 'DT3104']),
    );
  });

  test(
    'local refs may cycle but symlinks may not escape the project',
    () async {
      final root = await Directory.systemTemp.createTemp('dartitect-openapi-');
      final outside = await Directory.systemTemp.createTemp(
        'dartitect-openapi-outside-',
      );
      addTearDown(() async {
        await root.delete(recursive: true);
        await outside.delete(recursive: true);
      });
      final recursive = _contract();
      final schemas =
          ((recursive['components']! as Map<String, Object?>)['schemas']!
              as Map<String, Object?>);
      schemas['Node'] = <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'next': <String, Object?>{r'$ref': '#/components/schemas/Node'},
        },
      };
      await _writeJson(root, 'recursive.json', recursive);
      expect(
        (await OpenApiContractService(root).inspect(specPath: 'recursive.json'))
            .isValid,
        isTrue,
      );

      if (!Platform.isWindows) {
        final outsideFile = File('${outside.path}/outside.json');
        await outsideFile.writeAsString(jsonEncode(_contract()));
        await Link('${root.path}/escaped.json')
            .create(outsideFile.path, recursive: true);
        final escaped = await OpenApiContractService(root)
            .inspect(specPath: 'escaped.json');
        expect(escaped.isValid, isFalse);
        expect(escaped.findings.single.code, 'DT3101');
        expect(escaped.findings.single.message, contains('escapes'));
      }
    },
  );
}

Map<String, Object?> _contract({
  bool extraProperty = false,
  bool requireExtraProperty = false,
}) => <String, Object?>{
  'openapi': '3.1.0',
  'info': <String, Object?>{'title': 'Test API', 'version': '1'},
  'paths': <String, Object?>{
    '/tasks/{id}': <String, Object?>{
      'get': <String, Object?>{
        'operationId': 'getTask',
        'parameters': <Object?>[
          <String, Object?>{
            'name': 'id',
            'in': 'path',
            'required': true,
            'schema': <String, Object?>{
              'type': 'string',
              'format': 'consumer-opaque',
            },
          },
        ],
        'responses': <String, Object?>{
          '200': <String, Object?>{
            'description': 'ok',
            'content': <String, Object?>{
              'application/json': <String, Object?>{
                'schema': <String, Object?>{
                  r'$ref': '#/components/schemas/Task',
                },
              },
            },
          },
        },
      },
    },
  },
  'components': <String, Object?>{
    'schemas': <String, Object?>{
      'Task': <String, Object?>{
        'type': 'object',
        'required': <Object?>['id', if (requireExtraProperty) 'note'],
        'properties': <String, Object?>{
          'id': <String, Object?>{'type': 'string'},
          if (extraProperty) 'note': <String, Object?>{'type': 'string'},
        },
      },
    },
  },
};

Future<void> _writeJson(
  Directory root,
  String relativePath,
  Map<String, Object?> value,
) async {
  final file = File('${root.path}/$relativePath');
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode(value));
}
