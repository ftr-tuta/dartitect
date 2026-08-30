import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:dartitect_cli/dartitect_contracts.dart';
import 'package:dartitect_devtools/dartitect_devtools.dart';
import 'package:dartitect_lints/main.dart';
import 'package:dartitect_mcp/dartitect_mcp.dart';
import 'package:dartitect_modeling_analyzer/dartitect_modeling_analyzer.dart';
import 'package:dartitect_testing/dartitect_testing.dart';

/// Public tooling types imported through their packaged entrypoints.
const toolingTypes = <Type>[
  DartitectBlueprintService,
  OpenApiContractService,
  DartitectDevToolsRegistration,
  DartitectPlugin,
  DartitectMcpPolicy,
  ModelingCompiler,
  ResourceCensus,
];

/// Read-only DevTools endpoint proves the production entrypoint is linked.
const toolingExtension = dartitectCapabilitiesExtension;
