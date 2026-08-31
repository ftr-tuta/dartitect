/// Opt-in Flutter integration for Dartitect's owned reactive runtime.
///
/// This entrypoint is intentionally separate from `dartitect_flutter.dart` so
/// existing consumers do not pay for or accidentally adopt advanced reactive
/// APIs. It never exports Material widgets.
library;

export 'src/binding_diagnostics.dart';
export 'src/reactive/causal_refresh.dart';
export 'src/reactive/debounced_reactive_value.dart';
export 'src/reactive/derived_async_resource.dart';
export 'src/reactive/lifecycle_barrier.dart';
export 'src/reactive/live_collection.dart';
export 'src/reactive/live_resource.dart';
export 'src/reactive/paged_live_resource.dart';
export 'src/reactive/pull_reactive_source.dart';
export 'src/reactive/reactive_builders.dart';
export 'src/reactive/reactive_owner.dart';
export 'src/reactive/reactive_selector.dart';
export 'src/reactive/reactive_sources.dart';
export 'src/reactive/resource_family.dart';
export 'src/reactive/resource_lifecycle.dart';
export 'src/reactive/resource_presentation.dart';
export 'src/reactive/resource_presentation_builder.dart';
