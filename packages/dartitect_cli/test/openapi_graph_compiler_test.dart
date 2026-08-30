import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:dartitect_cli/dartitect_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('accepts only fresh, explicitly selected operation IDs', () async {
    final root = await Directory.systemTemp.createTemp(
      'dartitect-openapi-graph-',
    );
    addTearDown(() => root.delete(recursive: true));
    final spec = File('${root.path}/contracts/api.json');
    await spec.parent.create(recursive: true);
    await spec.writeAsString(jsonEncode(_contract));
    await OpenApiContractService(root).apply(specPath: 'contracts/api.json');

    final reports = await DartitectOpenApiGraphCompiler(root)
        .compile(_config('getTask'));
    expect(reports['api']!.operationIds, <String>{'getTask'});
    expect(reports['api']!.operationTypes, <String, String>{
      'getTask': 'GetTaskOperation',
    });

    await expectLater(
      DartitectOpenApiGraphCompiler(root).compile(_config('deleteTask')),
      throwsA(
        isA<DartitectConfigException>().having(
          (error) => error.message,
          'message',
          contains('is not declared'),
        ),
      ),
    );

    await spec.writeAsString(
      jsonEncode(<String, Object?>{
        ..._contract,
        'info': <String, Object?>{'title': 'Changed', 'version': '2'},
      }),
    );
    await expectLater(
      DartitectOpenApiGraphCompiler(root).compile(_config('getTask')),
      throwsA(
        isA<DartitectConfigException>().having(
          (error) => error.message,
          'message',
          contains('output is stale'),
        ),
      ),
    );
  });
}

DartitectConfig _config(String operationId) {
  const targets = <DartitectPlatform>[DartitectPlatform.android];
  return DartitectConfig(
    targets: DartitectTargetsConfig(targets),
    transports: <String, DartitectTransportConfig>{
      'api': DartitectTransportConfig(provider: 'dio', targets: targets),
    },
    contracts: <String, DartitectContractConfig>{
      'api': DartitectContractConfig(
        spec: 'contracts/api.json',
        output: 'lib/contracts/api.contracts.dartitect.g.dart',
        transport: 'api',
      ),
    },
    features: DartitectFeaturesConfig(
      declarations: <String, DartitectFeatureDeclaration>{
        'tasks': DartitectFeatureDeclaration(
          profile: FeatureProfile.online,
          scope: FeatureScope.application,
          transport: 'api',
          pagination: FeaturePagination.none,
          diagnostics: FeatureDiagnosticsLevel.basic,
          operations: <DartitectOpenApiOperationConfig>[
            DartitectOpenApiOperationConfig(
              contract: 'api',
              operationId: operationId,
            ),
          ],
        ),
      },
    ),
  );
}

const _contract = <String, Object?>{
  'openapi': '3.1.0',
  'info': <String, Object?>{'title': 'Tasks', 'version': '1'},
  'paths': <String, Object?>{
    '/tasks/{id}': <String, Object?>{
      'get': <String, Object?>{
        'operationId': 'getTask',
        'parameters': <Object?>[
          <String, Object?>{
            'name': 'id',
            'in': 'path',
            'required': true,
            'schema': <String, Object?>{'type': 'string'},
          },
        ],
        'responses': <String, Object?>{
          '200': <String, Object?>{'description': 'ok'},
        },
      },
    },
  },
};
