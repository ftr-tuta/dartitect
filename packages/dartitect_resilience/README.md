# Dartitect Resilience

`dartitect_resilience` provides bounded, provider-neutral retry,
single-flight, circuit-breaker, bulkhead, and rate-limiter primitives. It
depends only on `dartitect`.

Expected failures remain typed `Result` values. A consumer classifies the exact
failure types that may retry; uncertain mutations never retry automatically.
Unexpected exceptions remain crashes. Clocks, schedulers, and randomness are
injectable for deterministic tests.

The package does not define HTTP policy, remote idempotency, auth, scheduling,
storage, or a universal failure taxonomy.

