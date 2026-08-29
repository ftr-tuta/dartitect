/// Stable credential lifecycle primitives with consumer-owned storage.
library;

export 'dartitect.dart'
    show
        AsyncDisposable,
        CancellationException,
        CancellationSignal,
        Result,
        Ok,
        Err;
export 'src/credentials/credentials.dart';
