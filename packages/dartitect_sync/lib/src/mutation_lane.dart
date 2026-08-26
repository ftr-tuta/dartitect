import 'offline/mutation_command.dart';

/// Offline-first mutation lane owned by a repository or sync graph.
///
/// The implementation preserves the pre-1.0 prototype while the stable owner
/// is now `dartitect_sync`. The generic order follows aggregate key, argument,
/// remote value, and expected failure.
typedef MutationLane<K, A, T, F extends Object> = MutationCommand<A, K, T, F>;
