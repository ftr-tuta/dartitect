# Results and commands

Use `Result<T, F>` only for expected failures a caller can handle. Do not erase
failure types, stringify them at the domain boundary, or translate an unexpected
exception into `Err` without an explicit recovery contract.

`Command0<T, F>`, `Command1<A, T, F>`, and dedicated
`KeyedCommand1<K, A, T, F>` expose expected `Err<F>` as state and do not report
it automatically. Reject is the default; join, drop, bounded sequential,
restart-latest, bounded concurrent, and bounded keyed policies are explicit. An
unexpected exception transitions to crashed, can be reported once through an
injected reporter, and is rethrown. A disposed command is terminal and does not
notify. One-shot navigation/snackbar effects use a bounded, route-owned,
single-consumer channel rather than being replayed as command data.

All Flutter commands implement `DartitectCommand<T, F>` and
`DartitectObservableResource`, so ownership is compile-time safe. Consume
`CommandState` through exhaustive `match` callbacks for idle, running,
succeeded, failed, crashed, and cancelled states; each callback receives the
complete state.

Use `OperationProgress<P>` and `CommandExecutionContext<P>` for typed bounded
progress. Execution IDs fence old work and sequences increase within one
execution. `ProgressCommand0`, `ProgressCommand1`, and `KeyedProgressCommand1`
retain the established concurrency contracts and reject late progress.
