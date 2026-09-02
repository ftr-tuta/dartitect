/// Opt-in bounded incremental execution primitives for Dart applications.
///
/// The stable `dartitect.dart` entrypoint remains unchanged. Import this
/// library only for cold producer execution, explicit backpressure, bounded
/// collection, and incremental reduction.
library;

export 'dartitect.dart'
    show
        CancellationException,
        CancellationRegistration,
        CancellationSignal,
        CancellationSource,
        Err,
        Ok,
        OperationDeadlineExceededException,
        Result;
export 'src/incremental/incremental.dart';
