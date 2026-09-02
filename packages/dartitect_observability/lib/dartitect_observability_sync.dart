/// Explicit observability adapter for `dartitect_sync`.
///
/// Kept separate so importing the core observability entrypoint does not add
/// sync symbols to consumer source files.
library;

export 'src/sync_observability_adapter.dart';
