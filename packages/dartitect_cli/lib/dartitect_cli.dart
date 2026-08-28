/// Zero-dependency architecture inspection and generation for Dartitect.
library;

export 'src/cli/dartitect_cli_runner.dart';
export 'src/codex/codex_skill_synchronizer.dart';
export 'src/config/dartitect_config.dart';
export 'src/diagnostics/models.dart';
export 'src/diagnostics/sarif.dart';
export 'src/fleet/fleet_canary_service.dart';
export 'src/fleet/fleet_service.dart';
export 'src/generation/generation_engine.dart';
export 'src/generation/scaffolds.dart';
export 'src/model/model_generator.dart';
export 'src/model/primary_constructor_migration.dart';
export 'src/policy/ecosystem_policy.dart';
export 'src/project/dartitect_project_service.dart';
export 'src/rules/boundary_rules.dart';
export 'src/scan/baseline.dart';
export 'src/scan/project_scanner.dart';
export 'src/verification/verification_service.dart';
