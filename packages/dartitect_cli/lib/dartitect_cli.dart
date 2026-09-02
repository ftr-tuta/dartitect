/// Zero-dependency architecture inspection and generation for Dartitect.
library;

export 'package:dartitect/dartitect.dart' show FeatureProfile;

export 'src/blueprints/blueprint_service.dart';
export 'src/cli/dartitect_cli_runner.dart';
export 'src/codex/codex_skill_synchronizer.dart'
    show CodexSkillSynchronizer, CodexSyncResult;
export 'src/config/dartitect_config.dart';
export 'src/diagnostics/models.dart';
export 'src/diagnostics/sarif.dart';
export 'src/extensions/local_extension_compiler.dart';
export 'src/factories/semantic_factory_compiler.dart';
export 'src/fleet/fleet_canary_service.dart';
export 'src/fleet/fleet_service.dart';
export 'src/fleet/v2_config_migration.dart';
export 'src/generation/generation_engine.dart';
export 'src/generation/scaffolds.dart';
export 'src/generation/wiring_service.dart';
export 'src/inspect/consumer_tax.dart';
export 'src/inspect/execution_model.dart';
export 'src/model/model_generator.dart';
export 'src/policy/ecosystem_policy.dart';
export 'src/project/dartitect_project_service.dart';
export 'src/rules/boundary_rules.dart';
export 'src/scan/project_scanner.dart';
export 'src/ui/ui_auditor.dart';
export 'src/verification/verification_service.dart';
