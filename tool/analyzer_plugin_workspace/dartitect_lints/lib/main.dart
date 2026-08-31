/// Analyzer-plugin entrypoint for Dartitect architecture diagnostics.
library;

import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/dartitect_boundary_rule.dart';
import 'src/dartitect_modeling_rule.dart';
import 'src/dartitect_ui_rule.dart';

/// Entrypoint discovered by the official analysis server plugin host.
final plugin = DartitectPlugin();

/// Registers Dartitect architecture diagnostics as default warnings.
final class DartitectPlugin extends Plugin {
  @override
  String get name => 'Dartitect architecture rules';

  @override
  void register(PluginRegistry registry) {
    registry.registerWarningRule(DartitectBoundaryRule());
    registry.registerWarningRule(DartitectModelingRule());
    registry.registerWarningRule(DartitectUiRule());
    registry.registerFixForRule(
      DartitectModelingRule.primaryConstructor,
      DartitectPrimaryConstructorFix.new,
    );
  }
}
