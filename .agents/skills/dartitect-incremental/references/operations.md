# Incremental operations

Use `package:dartitect/dartitect_incremental.dart`. Construct
`IncrementalOperation.sync`, `.syncCloseable`, or `.async` with a factory that
creates a fresh source for each execution. Plain sync producers are only for
finite resource-free iterables; owned synchronous resources use the closeable
variant.

`IncrementalLimits` defaults to 100,000 emissions and 100,000 weight units.
Without `weightOf`, each successful item weighs one. Sequence numbers start at
one and timestamps use the injected UTC clock. `consume` retains no item;
`fold` returns the explicit aggregate and report; `collectBounded` returns the
explicit bounded items and report. Use `BoundedRingBuffer<T>` only when ordered
recent retention is an actual requirement.

Await `onValue` before the next emission. The first `Err` is terminal. Reject a
broadcast stream. Limit violations exclude the crossing item. A cancellation
or deadline cancels and awaits the subscription/source cleanup before returning
a cancelled or deadline report.
