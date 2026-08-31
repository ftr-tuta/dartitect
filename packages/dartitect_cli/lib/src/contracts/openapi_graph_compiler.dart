import 'dart:io';

import '../config/dartitect_config.dart';
import '../generation/generation_engine.dart';
import 'openapi_contract_service.dart';

/// Validates registered contracts and exact operation selections before wiring.
final class DartitectOpenApiGraphCompiler {
  /// Creates a compiler confined to one consumer project.
  DartitectOpenApiGraphCompiler(Directory root) : root = root.absolute;

  /// Consumer project boundary.
  final Directory root;

  /// Compiles contract surfaces without loading or executing generated code.
  Future<Map<String, OpenApiContractReport>> compile(
    DartitectConfig config,
  ) async {
    final reports = <String, OpenApiContractReport>{};
    final contracts = config.contracts.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    for (final entry in contracts) {
      final report = await OpenApiContractService(root)
          .inspect(specPath: entry.value.spec, outputPath: entry.value.output);
      final error = report.findings
          .where((finding) => finding.kind == OpenApiContractFindingKind.error)
          .firstOrNull;
      if (error != null) {
        throw DartitectConfigException(
          '/contracts/${_pointer(entry.key)}/spec',
          '${error.code} ${error.path}: ${error.message}',
        );
      }
      final outputs = report.plan?.operations.where(
        (operation) => operation.operation.relativePath == entry.value.output,
      );
      final target = outputs == null ? null : outputs.singleOrNull;
      if (target == null ||
          target.disposition != GenerationDisposition.noOp ||
          report.plan!.pendingRecovery) {
        throw DartitectConfigException(
          '/contracts/${_pointer(entry.key)}/output',
          'generated contract output is stale; run contracts sync first',
        );
      }
      reports[entry.key] = report;
    }

    for (final feature in config.features.declarations.entries) {
      for (var index = 0; index < feature.value.operations.length; index++) {
        final selection = feature.value.operations[index];
        final report = reports[selection.contract]!;
        if (!report.operationIds.contains(selection.operationId)) {
          throw DartitectConfigException(
            '/features/declarations/${_pointer(feature.key)}/operations/'
                '$index/operationId',
            'operationId "${selection.operationId}" is not declared by '
                'contract "${selection.contract}"',
          );
        }
      }
    }
    return Map<String, OpenApiContractReport>.unmodifiable(reports);
  }
}

String _pointer(String value) =>
    value.replaceAll('~', '~0').replaceAll('/', '~1');

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }

  T? get singleOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    final value = iterator.current;
    return iterator.moveNext() ? null : value;
  }
}
