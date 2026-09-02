# Isolate data and workers

Create a fresh isolate-local graph and exchange only sendable messages. Do not
transfer live clients, Stores, subscriptions, commands, owners, or closures
that capture them. Handler functions must satisfy the supported VM isolate
entry contract; fail explicitly on unsupported platforms.

`TransferableTypedData` transfers ownership after construction without an
automatic intermediate materialization. Keep it opaque through dispatch and
materialize only at the endpoint that needs bytes.

Cancellation acknowledges completion only after handler cleanup. A worker
crash never proves whether an admitted request applied, so replacement may
serve future work but must not replay the crashed request. Drain admitted work
before safe-stop unless an explicit terminal failure makes completion
impossible.
