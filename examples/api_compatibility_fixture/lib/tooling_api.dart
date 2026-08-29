import 'dart:io';

import 'package:dartitect_cli/dartitect_contracts.dart';

/// Representative tooling/test entrypoint separated from the CLI umbrella.
OpenApiContractService contractTool(Directory root) =>
    OpenApiContractService(root);
