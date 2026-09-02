# Streams and cancellation

A producer factory is an execution boundary: invoke it again for every run.
Single-subscription streams let the owner pause or cancel consumption; a
broadcast stream does not provide that ownership contract. Await the per-item
callback before pulling again rather than relying on an `async` listen callback
whose upstream continues unchecked.

On cancellation or deadline, stop accepting values, await
`StreamSubscription.cancel()`, and let an `async*` producer finish its
`finally` before exposing the terminal result. Fence generation/publication so
an already scheduled callback cannot publish afterward. Keep synchronous CPU
work bounded between emissions because cancellation cannot preempt it.

Do not promise cleanup for an arbitrary `Iterable`: Dart's `Iterator` has no
close method. Use finite resource-free iterables, or an owned source with an
explicit idempotent close callback. Cleanup errors stay named and retain their
original cause and stack.
