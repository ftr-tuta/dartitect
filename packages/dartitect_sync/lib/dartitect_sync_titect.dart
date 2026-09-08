/// Opt-in, bounded `titect-sync/1` wire contracts and incremental binding.
///
/// Transport, authentication, schemas, transactions, integrity policy and
/// conflict resolution belong to the consumer. Import the base sync entrypoint
/// separately when constructing an engine.
library;

export 'src/titect/binding.dart';
export 'src/titect/codec.dart';
export 'src/titect/json.dart';
