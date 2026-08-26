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
